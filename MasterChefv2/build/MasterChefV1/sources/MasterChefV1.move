module MasterChefDeployer::MasterChefV1 {
    use MosquitoCoinDeployer::MosquitoCoin::{ Self, SUCKR };
    use std::signer;
    use std::vector;
    use std::event;
    use std::type_info::{ Self, TypeInfo };
    use aptos_framework::timestamp;
    use aptos_framework::coin::{ Self, Coin };
    use aptos_framework::account::{ Self, SignerCapability };

    // When new block is not generated yet
    const ERR_WAIT_FOR_NEW_BLOCK: u64 = 100;
    // When already exists on account
    const ERR_POOL_ALREADY_EXIST: u64 = 101;
    // When not exists on account
    const ERR_POOL_NOT_EXIST: u64 = 102;
    // When not greater than zero;
    const ERR_MUST_BE_GREATER_THAN_ZERO: u64 = 103;
    // When not exists on account
    const ERR_USERINFO_NOT_EXIST: u64 = 104;
    // When insufficient balance
    const ERR_INSUFFICIENT_BALANCE: u64 = 105;
    // When user is not admin
    const ERR_FORBIDDEN: u64 = 106;
    // When farm is not started
    const ERR_FARM_NOT_STARTED: u64 = 107;
    // When farm is already started
    const ERR_FARM_ALREADY_STARTED: u64 = 108;

    const MAX_DEPOSIT_FEE: u64 = 20;     // 2%
    const PERCENT_PRECISION: u64 = 1000;
    const ACC_REWARD_PRECISION: u128 = 100000000;
    const MAX_REWARD_TOKEN_RATE: u128 = 100000000;      // 1 SUCKR per second

    const DEPLOYER_ADDRESS: address = @MasterChefDeployer;
    const RESOURCE_ACCOUNT_ADDRESS: address = @MasterChefResourceAccount;

    // Store staked LP info under masterchef
    struct LPInfo has key {
        lp_list: vector<TypeInfo>
    }

    // Store available pool info under masterchef
    struct PoolInfo<phantom CoinType> has key, store {
        fee: u64,
        alloc_point: u128,
        total_share: u128,
        acc_reward_per_share: u128,
        last_reward_timestamp: u64,
        coin_reserve: Coin<CoinType>,
    }

    // Store user info under user account
    struct UserInfo<phantom CoinType> has key, copy, store {
        amount: u64,
        reward_debt: u128,
    }

    // Store all admindata under masterchef
    struct MasterChefData has key {
        signer_cap: SignerCapability,
        admin_address: address,
        dev_address: address,
        team_address: address,
        team_percent: u64,
        last_timestamp_team_withdraw: u64,
        marketing_address: address,
        marketing_percent: u64,
        last_timestamp_marketing_withdraw: u64,
        lottery_address: address,
        lottery_percent: u64,
        last_timestamp_lottery_withdraw: u64,
        burn_address: address,
        burn_percent: u64,
        last_timestamp_burn_withdraw: u64,
        farming_percent: u64,
        total_alloc_point: u128,
        per_second_reward: u128,
        farm_enabled: bool,
    }

    struct Events has key {
        deposit_event: event::EventHandle<DepositEvent>,
        withdraw_event: event::EventHandle<WithdrawEvent>,
        emergency_withdraw_event: event::EventHandle<WithdrawEvent>,
    }

    struct DepositEvent has drop, store {
        coin_type: TypeInfo,
        amount: u64,
    }

    struct WithdrawEvent has drop, store {
        coin_type: TypeInfo,
        amount: u64,
    }

    public entry fun initialize(admin: &signer) acquires MasterChefData, LPInfo {
        let admin_addr = signer::address_of(admin);
        let current_timestamp = timestamp::now_seconds();
        let (resource_account_signer, signer_cap) = account::create_resource_account(admin, x"30");
        
        move_to(admin, MasterChefData {
            signer_cap: signer_cap,
            admin_address: admin_addr,
            dev_address: admin_addr,
            team_address: admin_addr,
            team_percent: 1,
            last_timestamp_team_withdraw: current_timestamp,
            marketing_address: admin_addr,
            marketing_percent: 9,
            last_timestamp_marketing_withdraw: current_timestamp,
            lottery_address: admin_addr,
            lottery_percent: 90,
            last_timestamp_lottery_withdraw: current_timestamp,
            burn_address: admin_addr,
            burn_percent: 100,
            last_timestamp_burn_withdraw: current_timestamp,
            farming_percent: 800,
            total_alloc_point: 0,
            per_second_reward: 3333333,
            farm_enabled: false
        });
        move_to(admin, LPInfo {
            lp_list: vector::empty(),
        });
        move_to(&resource_account_signer, Events {
            deposit_event: account::new_event_handle<DepositEvent>(&resource_account_signer),
            withdraw_event: account::new_event_handle<WithdrawEvent>(&resource_account_signer),
            emergency_withdraw_event: account::new_event_handle<WithdrawEvent>(&resource_account_signer),
        });

        // SUCKR staking
        add<SUCKR>(admin, 1000, 0);
    }

/// functions list for view info ///
    // Get resource account address
    public fun get_resource_address(): address acquires MasterChefData {
        let resource_account_signer = get_resource_account_signer();
        signer::address_of(&resource_account_signer)
    }

    // return resource account signer
    fun get_resource_account_signer(): signer acquires MasterChefData {
        let signer_cap = &borrow_global<MasterChefData>(DEPLOYER_ADDRESS).signer_cap;
        account::create_signer_with_capability(signer_cap)
    }

    // Get user deposit amount
    public fun get_user_info<CoinType>(
        user_addr: address
    ): (u64) acquires UserInfo {
        assert!(exists<UserInfo<CoinType>>(user_addr), ERR_USERINFO_NOT_EXIST);
        let user_info = borrow_global<UserInfo<CoinType>>(user_addr);
        (user_info.amount)
    }

    // Get the pending reward token amount
    public fun get_pending_rewardtoken<CoinType>(
        user_addr: address
    ): u128 acquires PoolInfo, UserInfo, MasterChefData {
        assert!(exists<UserInfo<CoinType>>(user_addr), ERR_USERINFO_NOT_EXIST);

        let user_info = borrow_global<UserInfo<CoinType>>(user_addr);
        let pool_info = borrow_global<PoolInfo<CoinType>>(RESOURCE_ACCOUNT_ADDRESS);
        let mc_data = borrow_global<MasterChefData>(DEPLOYER_ADDRESS);
        let current_timestamp = timestamp::now_seconds();
        let acc_reward_per_share = pool_info.acc_reward_per_share;

        if (current_timestamp > pool_info.last_reward_timestamp && pool_info.total_share > 0) {
            let multiplier = current_timestamp - pool_info.last_reward_timestamp;
            let reward_amount = (multiplier as u128) * mc_data.per_second_reward * pool_info.alloc_point / mc_data.total_alloc_point;
            reward_amount = reward_amount * (mc_data.farming_percent as u128) / (PERCENT_PRECISION as u128);
            acc_reward_per_share = acc_reward_per_share + reward_amount * ACC_REWARD_PRECISION / pool_info.total_share;
        };
        (user_info.amount as u128) * acc_reward_per_share / ACC_REWARD_PRECISION - user_info.reward_debt
    }

/// functions list for only owner ///
    // Enable the farm
    public entry fun enable_farm(admin: &signer) acquires MasterChefData {
        let mc_data = borrow_global_mut<MasterChefData>(DEPLOYER_ADDRESS);
        assert!(signer::address_of(admin) == mc_data.admin_address, ERR_FORBIDDEN);
        assert!(mc_data.farm_enabled == false, ERR_FARM_ALREADY_STARTED);
        
        mc_data.farm_enabled = true;
    }

    // Set admin address
    public entry fun set_admin_address(
        admin: &signer,
        new_admin_address: address
    ) acquires MasterChefData {
        let mc_data = borrow_global_mut<MasterChefData>(DEPLOYER_ADDRESS);
        assert!(signer::address_of(admin) == mc_data.admin_address, ERR_FORBIDDEN);
        mc_data.admin_address = new_admin_address;
    }

    // Set dev address
    public entry fun set_dev_address(
        admin: &signer,
        dev_address: address
    ) acquires MasterChefData {
        let mc_data = borrow_global_mut<MasterChefData>(DEPLOYER_ADDRESS);
        assert!(signer::address_of(admin) == mc_data.admin_address, ERR_FORBIDDEN);
        mc_data.dev_address = dev_address;
    }

    // Set team address
    public entry fun set_team_address(
        admin: &signer,
        team_address: address
    ) acquires MasterChefData {
        let mc_data = borrow_global_mut<MasterChefData>(DEPLOYER_ADDRESS);
        assert!(signer::address_of(admin) == mc_data.admin_address, ERR_FORBIDDEN);
        mc_data.team_address = team_address;
    }

    // Set market address
    public entry fun set_market_address(
        admin: &signer,
        marketing_address: address
    ) acquires MasterChefData {
        let mc_data = borrow_global_mut<MasterChefData>(DEPLOYER_ADDRESS);
        assert!(signer::address_of(admin) == mc_data.admin_address, ERR_FORBIDDEN);
        mc_data.marketing_address = marketing_address;
    }

    // Set lottery address
    public entry fun set_lottery_address(
        admin: &signer,
        lottery_address: address
    ) acquires MasterChefData {
        let mc_data = borrow_global_mut<MasterChefData>(DEPLOYER_ADDRESS);
        assert!(signer::address_of(admin) == mc_data.admin_address, ERR_FORBIDDEN);
        mc_data.lottery_address = lottery_address;
    }

    // Set burn address
    public entry fun set_burn_address(
        admin: &signer,
        burn_address: address
    ) acquires MasterChefData {
        let mc_data = borrow_global_mut<MasterChefData>(DEPLOYER_ADDRESS);
        assert!(signer::address_of(admin) == mc_data.admin_address, ERR_FORBIDDEN);
        mc_data.burn_address = burn_address;
    }

    // Set reward token amount per second
    public entry fun set_per_second_reward(
        admin: &signer,
        per_second_reward: u128
    ) acquires MasterChefData {
        let mc_data = borrow_global_mut<MasterChefData>(DEPLOYER_ADDRESS);
        assert!(signer::address_of(admin) == mc_data.admin_address, ERR_FORBIDDEN);
        mc_data.per_second_reward = if (MAX_REWARD_TOKEN_RATE > per_second_reward) {
            per_second_reward
        } else {
            MAX_REWARD_TOKEN_RATE
        }
    }

    // Add a new pool
    public entry fun add<CoinType>(
        admin: &signer,
        alloc_point: u128,
        fee: u64
    ) acquires MasterChefData, LPInfo {
        let resource_account_signer = get_resource_account_signer();
        let lp_info = borrow_global_mut<LPInfo>(DEPLOYER_ADDRESS);
        let mc_data = borrow_global_mut<MasterChefData>(DEPLOYER_ADDRESS);

        assert!(signer::address_of(admin) == mc_data.admin_address, ERR_FORBIDDEN);
        assert!(!exists<PoolInfo<CoinType>>(RESOURCE_ACCOUNT_ADDRESS), ERR_POOL_ALREADY_EXIST);

        let current_timestamp = timestamp::now_seconds();
        let pool_fee = if (MAX_DEPOSIT_FEE > fee) {
            fee
        } else {
            MAX_DEPOSIT_FEE
        };
        mc_data.total_alloc_point = mc_data.total_alloc_point + alloc_point;
        move_to(&resource_account_signer, PoolInfo<CoinType> {
            fee: pool_fee,
            total_share: 0,
            acc_reward_per_share: 0,
            alloc_point: alloc_point,
            last_reward_timestamp: current_timestamp,
            coin_reserve: coin::zero(),
        });
        vector::push_back<TypeInfo>(&mut lp_info.lp_list, type_info::type_of<CoinType>());
    }

    // Set the existing pool
    public entry fun set<CoinType>(
        admin: &signer,
        alloc_point: u128,
        fee: u64,
    ) acquires MasterChefData, PoolInfo {
        let mc_data = borrow_global_mut<MasterChefData>(DEPLOYER_ADDRESS);

        assert!(signer::address_of(admin) == mc_data.admin_address, ERR_FORBIDDEN);
        assert!(exists<PoolInfo<CoinType>>(RESOURCE_ACCOUNT_ADDRESS), ERR_POOL_NOT_EXIST);

        let pool_info = borrow_global_mut<PoolInfo<CoinType>>(RESOURCE_ACCOUNT_ADDRESS);
        mc_data.total_alloc_point = mc_data.total_alloc_point - pool_info.alloc_point + alloc_point;
        pool_info.alloc_point = alloc_point;
        pool_info.fee = if (MAX_DEPOSIT_FEE > fee) {
            fee
        } else {
            MAX_DEPOSIT_FEE
        };
    }

    // Withdraw dev fee
    public entry fun withdraw_dev_fee<CoinType>(dev_account: &signer) acquires MasterChefData, PoolInfo {
        let mc_data = borrow_global_mut<MasterChefData>(DEPLOYER_ADDRESS);
        assert!(signer::address_of(dev_account) == mc_data.dev_address, ERR_FORBIDDEN);

        let pool_info = borrow_global_mut<PoolInfo<CoinType>>(RESOURCE_ACCOUNT_ADDRESS);
        let amount_out = coin::value(&pool_info.coin_reserve) - (pool_info.total_share as u64);
        let coins_out = coin::extract(&mut pool_info.coin_reserve, amount_out);
        if (!coin::is_account_registered<CoinType>(signer::address_of(dev_account))) {
            coin::register<CoinType>(dev_account);
        };
        coin::deposit<CoinType>(signer::address_of(dev_account), coins_out);
    }

    // Withdraw the reward token for team
    public entry fun withdraw_for_team(team_account: &signer) acquires MasterChefData {
        let resource_account_signer = get_resource_account_signer();
        let mc_data = borrow_global_mut<MasterChefData>(DEPLOYER_ADDRESS);
        let current_timestamp = timestamp::now_seconds();
        let team_addr = signer::address_of(team_account);
        assert!(team_addr == mc_data.team_address, ERR_FORBIDDEN);
        assert!(mc_data.last_timestamp_team_withdraw < current_timestamp, ERR_WAIT_FOR_NEW_BLOCK);

        let multiplier = ((current_timestamp - mc_data.last_timestamp_team_withdraw) as u128);
        let pending_amount = multiplier * mc_data.per_second_reward * (mc_data.team_percent as u128) / (PERCENT_PRECISION as u128);
        let coins_out = MosquitoCoin::mint_farm_SUCKR(&resource_account_signer, (pending_amount as u64));
        if (!coin::is_account_registered<SUCKR>(team_addr)) {
            coin::register<SUCKR>(team_account);
        };
        mc_data.last_timestamp_team_withdraw = current_timestamp;
        coin::deposit<SUCKR>(team_addr, coins_out);
    }

    // Withdraw the reward token for marketing
    public entry fun withdraw_for_marketing(marketing_account: &signer) acquires MasterChefData {
        let resource_account_signer = get_resource_account_signer();
        let mc_data = borrow_global_mut<MasterChefData>(DEPLOYER_ADDRESS);
        let current_timestamp = timestamp::now_seconds();
        let marketing_addr = signer::address_of(marketing_account);
        assert!(marketing_addr == mc_data.marketing_address, ERR_FORBIDDEN);
        assert!(mc_data.last_timestamp_marketing_withdraw < current_timestamp, ERR_WAIT_FOR_NEW_BLOCK);

        let multiplier = ((current_timestamp - mc_data.last_timestamp_marketing_withdraw) as u128);
        let pending_amount = multiplier * mc_data.per_second_reward * (mc_data.marketing_percent as u128) / (PERCENT_PRECISION as u128);
        let coins_out = MosquitoCoin::mint_farm_SUCKR(&resource_account_signer, (pending_amount as u64));
        if (!coin::is_account_registered<SUCKR>(marketing_addr)) {
            coin::register<SUCKR>(marketing_account);
        };
        mc_data.last_timestamp_marketing_withdraw = current_timestamp;
        coin::deposit<SUCKR>(marketing_addr, coins_out);
    }

    // Withdraw the reward token for lottery
    public entry fun withdraw_for_lottery(lottery_account: &signer) acquires MasterChefData {
        let resource_account_signer = get_resource_account_signer();
        let mc_data = borrow_global_mut<MasterChefData>(DEPLOYER_ADDRESS);
        let current_timestamp = timestamp::now_seconds();
        let lottery_addr = signer::address_of(lottery_account);
        assert!(lottery_addr == mc_data.lottery_address, ERR_FORBIDDEN);
        assert!(mc_data.last_timestamp_lottery_withdraw < current_timestamp, ERR_WAIT_FOR_NEW_BLOCK);

        let multiplier = ((current_timestamp - mc_data.last_timestamp_lottery_withdraw) as u128);
        let pending_amount = multiplier * mc_data.per_second_reward * (mc_data.lottery_percent as u128) / (PERCENT_PRECISION as u128);
        let coins_out = MosquitoCoin::mint_farm_SUCKR(&resource_account_signer, (pending_amount as u64));
        if (!coin::is_account_registered<SUCKR>(lottery_addr)) {
            coin::register<SUCKR>(lottery_account);
        };
        mc_data.last_timestamp_lottery_withdraw = current_timestamp;
        coin::deposit<SUCKR>(lottery_addr, coins_out);
    }

    // Withdraw the reward token for burn
    public entry fun withdraw_for_burn(burn_account: &signer) acquires MasterChefData {
        let resource_account_signer = get_resource_account_signer();
        let mc_data = borrow_global_mut<MasterChefData>(DEPLOYER_ADDRESS);
        let current_timestamp = timestamp::now_seconds();
        let burn_addr = signer::address_of(burn_account);
        assert!(burn_addr == mc_data.burn_address, ERR_FORBIDDEN);
        assert!(mc_data.last_timestamp_burn_withdraw < current_timestamp, ERR_WAIT_FOR_NEW_BLOCK);

        let multiplier = ((current_timestamp - mc_data.last_timestamp_burn_withdraw) as u128);
        let pending_amount = multiplier * mc_data.per_second_reward * (mc_data.burn_percent as u128) / (PERCENT_PRECISION as u128);
        let coins_out = MosquitoCoin::mint_farm_SUCKR(&resource_account_signer, (pending_amount as u64));
        if (!coin::is_account_registered<SUCKR>(burn_addr)) {
            coin::register<SUCKR>(burn_account);
        };
        mc_data.last_timestamp_burn_withdraw = current_timestamp;
        coin::deposit<SUCKR>(burn_addr, coins_out);
    }

/// functions list for every user ///
    // Update pool info
    fun update_pool<CoinType>() acquires MasterChefData, PoolInfo {
        assert!(exists<PoolInfo<CoinType>>(RESOURCE_ACCOUNT_ADDRESS), ERR_POOL_NOT_EXIST);

        let resource_account_signer = get_resource_account_signer();
        let mc_data = borrow_global<MasterChefData>(DEPLOYER_ADDRESS);
        let current_timestamp = timestamp::now_seconds();
        let pool_info = borrow_global_mut<PoolInfo<CoinType>>(RESOURCE_ACCOUNT_ADDRESS);
        if (current_timestamp > pool_info.last_reward_timestamp) {
            if (mc_data.total_alloc_point > 0 && pool_info.total_share > 0) {
                let multiplier = ((current_timestamp - pool_info.last_reward_timestamp) as u128);
                let total_reward_amount = multiplier * mc_data.per_second_reward * pool_info.alloc_point / mc_data.total_alloc_point;
                let farm_reward_amount = total_reward_amount * (mc_data.farming_percent as u128) / (PERCENT_PRECISION as u128);
                let newly_generated_SUCKR = MosquitoCoin::mint_farm_SUCKR(&resource_account_signer, (farm_reward_amount as u64));
                coin::deposit(RESOURCE_ACCOUNT_ADDRESS, newly_generated_SUCKR);
                pool_info.acc_reward_per_share = pool_info.acc_reward_per_share + farm_reward_amount * ACC_REWARD_PRECISION / pool_info.total_share;
            };
            pool_info.last_reward_timestamp = current_timestamp;
        }
    }

    // Deposit LP tokens to pool
    public entry fun deposit<CoinType>(
        user_account: &signer,
        amount: u64
    ) acquires MasterChefData, UserInfo, PoolInfo, Events {
        update_pool<CoinType>();

        let resource_account_signer = get_resource_account_signer();
        let mc_data = borrow_global<MasterChefData>(DEPLOYER_ADDRESS);
        assert!(mc_data.farm_enabled == true, ERR_FARM_NOT_STARTED);

        let user_addr = signer::address_of(user_account);
        let pool_info = borrow_global_mut<PoolInfo<CoinType>>(RESOURCE_ACCOUNT_ADDRESS);
        let amount_in = amount - amount * pool_info.fee / PERCENT_PRECISION;
        if (exists<UserInfo<CoinType>>(user_addr)) {
            let user_info = borrow_global_mut<UserInfo<CoinType>>(user_addr);
            if (user_info.amount > 0) {
                let pending = (((user_info.amount as u128) * pool_info.acc_reward_per_share / ACC_REWARD_PRECISION - user_info.reward_debt) as u64);
                safe_transfer_SUCKR(&resource_account_signer, user_addr, pending);
            };
            user_info.amount = user_info.amount + amount_in;
            user_info.reward_debt = (user_info.amount as u128) * pool_info.acc_reward_per_share / ACC_REWARD_PRECISION;
        } else {
            move_to(user_account, UserInfo<CoinType> {
                amount: amount_in,
                reward_debt: (amount_in as u128) * pool_info.acc_reward_per_share / ACC_REWARD_PRECISION
            });
        };
        pool_info.total_share = pool_info.total_share + (amount_in as u128);
        let coins_in = coin::withdraw<CoinType>(user_account, amount);
        coin::merge(&mut pool_info.coin_reserve, coins_in);

        let events = borrow_global_mut<Events>(RESOURCE_ACCOUNT_ADDRESS);
        event::emit_event(&mut events.deposit_event, DepositEvent {
            coin_type: type_info::type_of<CoinType>(),
            amount: amount,
        });
    }

    // Withdraw LP tokens from pool
    public entry fun withdraw<CoinType>(
        user_account: &signer,
        amount_out: u64
    ) acquires MasterChefData, UserInfo, PoolInfo, Events {
        let user_addr = signer::address_of(user_account);
        assert!(exists<UserInfo<CoinType>>(user_addr), ERR_USERINFO_NOT_EXIST);

        update_pool<CoinType>();

        let resource_account_signer = get_resource_account_signer();
        let mc_data = borrow_global<MasterChefData>(DEPLOYER_ADDRESS);
        assert!(mc_data.farm_enabled == true, ERR_FARM_NOT_STARTED);

        let pool_info = borrow_global_mut<PoolInfo<CoinType>>(RESOURCE_ACCOUNT_ADDRESS);
        let user_info = borrow_global_mut<UserInfo<CoinType>>(user_addr);
        assert!(user_info.amount >= amount_out, ERR_INSUFFICIENT_BALANCE);

        let pending = (((user_info.amount as u128) * pool_info.acc_reward_per_share / ACC_REWARD_PRECISION - user_info.reward_debt) as u64);
        safe_transfer_SUCKR(&resource_account_signer, user_addr, pending);

        user_info.amount = user_info.amount - amount_out;
        user_info.reward_debt = (user_info.amount as u128) * pool_info.acc_reward_per_share / ACC_REWARD_PRECISION;
        pool_info.total_share = pool_info.total_share - (amount_out as u128);
        let coins_out = coin::extract(&mut pool_info.coin_reserve, amount_out);
        coin::deposit<CoinType>(user_addr, coins_out);

        let events = borrow_global_mut<Events>(RESOURCE_ACCOUNT_ADDRESS);
        event::emit_event(&mut events.withdraw_event, WithdrawEvent {
            coin_type: type_info::type_of<CoinType>(),
            amount: amount_out,
        });
    }

    // Withdraw without caring about the rewards. EMERGENCY ONLY
    public entry fun emergency_withdraw<CoinType>(
        user_account: &signer
    ) acquires MasterChefData, UserInfo, PoolInfo, Events {
        let user_addr = signer::address_of(user_account);
        assert!(exists<UserInfo<CoinType>>(user_addr), ERR_USERINFO_NOT_EXIST);

        let mc_data = borrow_global<MasterChefData>(DEPLOYER_ADDRESS);
        assert!(mc_data.farm_enabled == true, ERR_FARM_NOT_STARTED);
        
        let pool_info = borrow_global_mut<PoolInfo<CoinType>>(RESOURCE_ACCOUNT_ADDRESS);
        let user_info = borrow_global_mut<UserInfo<CoinType>>(user_addr);
        let amount_out = user_info.amount;
        assert!(amount_out > 0, ERR_MUST_BE_GREATER_THAN_ZERO);

        user_info.amount = 0;
        user_info.reward_debt = 0;
        pool_info.total_share = pool_info.total_share - (amount_out as u128);
        let coins_out = coin::extract(&mut pool_info.coin_reserve, amount_out);
        coin::deposit<CoinType>(user_addr, coins_out);

        let events = borrow_global_mut<Events>(RESOURCE_ACCOUNT_ADDRESS);
        event::emit_event(&mut events.emergency_withdraw_event, WithdrawEvent {
            coin_type: type_info::type_of<CoinType>(),
            amount: amount_out,
        });
    }

    // Stake SUCKR coins to MC
    public entry fun enter_staking(
        user_account: &signer,
        amount: u64
    ) acquires MasterChefData, UserInfo, PoolInfo, Events {
        deposit<SUCKR>(user_account, amount);
    }

    // Withdraw SUCKR coins from STAKING
    public entry fun leave_staking(
        user_account: &signer,
        amount: u64
    ) acquires MasterChefData, UserInfo, PoolInfo, Events {
        withdraw<SUCKR>(user_account, amount);
    }

/// function list for private
    // Transfer SUCKR to user
    fun safe_transfer_SUCKR(
        resource_account_signer: &signer,
        to: address,
        amount: u64
    ) {
        let balance = coin::balance<SUCKR>(signer::address_of(resource_account_signer));
        if (amount > balance) {
            coin::transfer<SUCKR>(resource_account_signer, to, balance);
        } else {
            coin::transfer<SUCKR>(resource_account_signer, to, amount);
        };
    }
}