module MasterChefDeployer::MasterChef {
    use MasterChefDeployer::MosquitoCoin::{ Self, SUCKR };
    use std::signer;
    use std::vector;
    use std::event;
    use std::type_info::{ Self, TypeInfo };
    use aptos_framework::timestamp;
    use aptos_framework::coin::{ Self };
    use aptos_framework::account::{ Self, SignerCapability };

    /// When already exists on account
    const ERR_POOL_ALREADY_EXIST: u64 = 101;
    /// When not exists on account
    const ERR_POOL_NOT_EXIST: u64 = 102;
    /// When not greater than zero;
    const ERR_MUST_BE_GREATER_THAN_ZERO: u64 = 103;
    /// When not exists on account
    const ERR_USERINFO_NOT_EXIST: u64 = 104;
    /// When insufficient balance
    const ERR_INSUFFICIENT_BALANCE: u64 = 105;
    /// When user is not admin
    const ERR_FORBIDDEN: u64 = 106;

    const PERCENT_PRECISION: u64 = 1000;
    const INIT_SUPPLY:u64 = 10000000000000;
    const ACC_REWARD_PRECISION: u128 = 100000000;

    const DEPLOYER_ADDRESS: address = @MasterChefDeployer;
    const RESOURCE_ACCOUNT_ADDRESS: address = @ResourceAccountDeployer;

    /// Store staked LP info under masterchef
    struct LPInfo has key {
        lp_list: vector<TypeInfo>
    }

    /// Store available pool info under masterchef
    struct PoolInfo<phantom CoinType> has key, store {
        fee: u64,
        multiplier: u64,
        alloc_point: u128,
        total_boosted_share: u128,
        acc_reward_per_share: u128,
        last_reward_timestamp: u64,
    }

    /// Store user info under user account
    struct UserInfo<phantom CoinType> has key, copy, store {
        amount: u64,
        reward_debt: u128,
        paid_reward_token_amount: u128,
    }

    /// Store all admindata under masterchef
    struct MasterChefData has key, drop {
        signer_cap: SignerCapability,
        admin_address: address,
        dev_address: address,
        team_address: address,
        team_percent: u64,
        pending_team_reward_token_amount: u64,
        marketing_address: address,
        marketing_percent: u64,
        pending_marketing_reward_token_amount: u64,
        lottery_address: address,
        lottery_percent: u64,
        pending_lottery_reward_token_amount: u64,
        burn_address: address,
        burn_percent: u64,
        pending_burn_reward_token_amount: u64,
        farming_percent: u64,
        bonus_multiplier: u64,
        total_alloc_point: u128,
        per_second_reward: u128,
        start_timestamp: u64,
        last_timestamp_mint: u64,
        last_timestamp_dev_withdraw: u64,
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

    public entry fun initialize(admin: &signer) {
        let admin_addr = signer::address_of(admin);
        let current_timestamp = timestamp::now_seconds();
        // let current_timestamp = 0;
        let (_, signer_cap) = account::create_resource_account(admin, x"30");
        let resource_account_signer = account::create_signer_with_capability(&signer_cap);
        
        MosquitoCoin::mint_SUCKR(&resource_account_signer, INIT_SUPPLY);

        move_to(admin, MasterChefData {
            signer_cap: signer_cap,
            admin_address: admin_addr,
            dev_address: admin_addr,
            team_address: admin_addr,
            team_percent: 1,
            pending_team_reward_token_amount: 0,
            marketing_address: admin_addr,
            marketing_percent: 9,
            pending_marketing_reward_token_amount: INIT_SUPPLY,
            lottery_address: admin_addr,
            lottery_percent: 90,
            pending_lottery_reward_token_amount: 0,
            burn_address: admin_addr,
            burn_percent: 100,
            pending_burn_reward_token_amount: 0,
            farming_percent: 800,
            bonus_multiplier: 1,
            total_alloc_point: 0,
            per_second_reward: 30000000,
            start_timestamp: current_timestamp,
            last_timestamp_mint: current_timestamp,
            last_timestamp_dev_withdraw: current_timestamp,
        });
        move_to(admin, LPInfo {
            lp_list: vector::empty(),
        });
        move_to(&resource_account_signer, Events {
            deposit_event: account::new_event_handle<DepositEvent>(&resource_account_signer),
            withdraw_event: account::new_event_handle<WithdrawEvent>(&resource_account_signer),
            emergency_withdraw_event: account::new_event_handle<WithdrawEvent>(&resource_account_signer),
        });
    }

/// functions list for view info ///
    /// Get resource account address
    public fun get_resource_address(): address acquires MasterChefData {
        let resource_account_signer = get_resource_account_signer();
        signer::address_of(&resource_account_signer)
    }

    /// return resource account signer
    public fun get_resource_account_signer(): signer acquires MasterChefData {
        let signer_cap = &borrow_global<MasterChefData>(DEPLOYER_ADDRESS).signer_cap;
        account::create_signer_with_capability(signer_cap)
    }

    /// Get boost multiplier
    public fun get_boost_multiplier(multiplier:u64): u128 {
        let boost_multiplier = (PERCENT_PRECISION as u128);
        if (multiplier > PERCENT_PRECISION) {
            boost_multiplier =  (multiplier as u128)
        };
        boost_multiplier
    }
    
    /// Get user deposit amount
    public fun get_user_info<CoinType>(
        user_addr: address
    ): (u64, u128) acquires UserInfo {
        assert!(exists<UserInfo<CoinType>>(user_addr), ERR_USERINFO_NOT_EXIST);
        let user_info = borrow_global<UserInfo<CoinType>>(user_addr);
        (user_info.amount, user_info.paid_reward_token_amount)
    }

    /// Get the pending reward token amount
    public fun get_pending_rewardtoken<CoinType>(
        user_addr: address
    ): u128 acquires PoolInfo, UserInfo, MasterChefData {
        let user_info = borrow_global<UserInfo<CoinType>>(user_addr);
        let pool_info = borrow_global<PoolInfo<CoinType>>(RESOURCE_ACCOUNT_ADDRESS);
        let masterchef_data = borrow_global<MasterChefData>(DEPLOYER_ADDRESS);
        let current_timestamp = timestamp::now_seconds();
        let acc_reward_per_share = pool_info.acc_reward_per_share;

        if (current_timestamp > pool_info.last_reward_timestamp && pool_info.total_boosted_share > 0) {
            let multiplier = current_timestamp - pool_info.last_reward_timestamp;
            let reward_amount = (multiplier as u128) * masterchef_data.per_second_reward * pool_info.alloc_point / masterchef_data.total_alloc_point;
            reward_amount = reward_amount * (masterchef_data.farming_percent as u128) / (PERCENT_PRECISION as u128);
            acc_reward_per_share = acc_reward_per_share + reward_amount * ACC_REWARD_PRECISION / (pool_info.total_boosted_share as u128);
        };
        (user_info.amount as u128) * acc_reward_per_share / ACC_REWARD_PRECISION - user_info.reward_debt
    }

/// functions list for only owner ///
    /// Set admin address
    public entry fun set_admin_address(
        admin: &signer,
        new_admin_address: address
    ) acquires MasterChefData {
        let masterchef_data = borrow_global_mut<MasterChefData>(DEPLOYER_ADDRESS);
        assert!(signer::address_of(admin) == masterchef_data.admin_address, ERR_FORBIDDEN);
        masterchef_data.admin_address = new_admin_address;
    }

    /// Set dev address
    public entry fun set_dev_address(
        admin: &signer,
        dev_address: address
    ) acquires MasterChefData {
        let masterchef_data = borrow_global_mut<MasterChefData>(DEPLOYER_ADDRESS);
        assert!(signer::address_of(admin) == masterchef_data.admin_address, ERR_FORBIDDEN);
        masterchef_data.dev_address = dev_address;
    }

    /// Set team address
    public entry fun set_team_address(
        admin: &signer,
        team_address: address
    ) acquires MasterChefData {
        let masterchef_data = borrow_global_mut<MasterChefData>(DEPLOYER_ADDRESS);
        assert!(signer::address_of(admin) == masterchef_data.admin_address, ERR_FORBIDDEN);
        masterchef_data.team_address = team_address;
    }

    /// Set market address
    public entry fun set_market_address(
        admin: &signer,
        marketing_address: address
    ) acquires MasterChefData {
        let masterchef_data = borrow_global_mut<MasterChefData>(DEPLOYER_ADDRESS);
        assert!(signer::address_of(admin) == masterchef_data.admin_address, ERR_FORBIDDEN);
        masterchef_data.marketing_address = marketing_address;
    }

    /// Set lottery address
    public entry fun set_lottery_address(
        admin: &signer,
        lottery_address: address
    ) acquires MasterChefData {
        let masterchef_data = borrow_global_mut<MasterChefData>(DEPLOYER_ADDRESS);
        assert!(signer::address_of(admin) == masterchef_data.admin_address, ERR_FORBIDDEN);
        masterchef_data.lottery_address = lottery_address;
    }

    /// Set burn address
    public entry fun set_burn_address(
        admin: &signer,
        burn_address: address
    ) acquires MasterChefData {
        let masterchef_data = borrow_global_mut<MasterChefData>(DEPLOYER_ADDRESS);
        assert!(signer::address_of(admin) == masterchef_data.admin_address, ERR_FORBIDDEN);
        masterchef_data.burn_address = burn_address;
    }

    /// Set reward token amount per second
    public entry fun set_per_second_reward(
        admin: &signer,
        per_second_reward: u128
    ) acquires MasterChefData {
        let masterchef_data = borrow_global_mut<MasterChefData>(DEPLOYER_ADDRESS);
        assert!(signer::address_of(admin) == masterchef_data.admin_address, ERR_FORBIDDEN);
        masterchef_data.per_second_reward = per_second_reward;
    }

    /// Set bonus
    public entry fun set_bonus_multiplier(
        admin: &signer,
        bonus_multiplier: u64
    ) acquires MasterChefData {
        let masterchef_data = borrow_global_mut<MasterChefData>(DEPLOYER_ADDRESS);
        assert!(signer::address_of(admin) == masterchef_data.admin_address, ERR_FORBIDDEN);
        masterchef_data.bonus_multiplier = bonus_multiplier;
    }

    /// Add a new pool
    public entry fun add<CoinType>(
        admin: &signer,
        alloc_point: u128,
        multiplier: u64,
        fee: u64
    ) acquires MasterChefData, LPInfo {
        let resource_account_signer = get_resource_account_signer();
        let existing_lp_info = borrow_global_mut<LPInfo>(DEPLOYER_ADDRESS);
        let masterchef_data = borrow_global_mut<MasterChefData>(DEPLOYER_ADDRESS);

        assert!(signer::address_of(admin) == masterchef_data.admin_address, ERR_FORBIDDEN);
        assert!(!exists<PoolInfo<CoinType>>(RESOURCE_ACCOUNT_ADDRESS), ERR_POOL_ALREADY_EXIST);

        let current_timestamp = timestamp::now_seconds();
        // let current_timestamp = 0;
        masterchef_data.total_alloc_point = masterchef_data.total_alloc_point + alloc_point;
        coin::register<CoinType>(&resource_account_signer);
        move_to(&resource_account_signer, PoolInfo<CoinType> {
            fee: fee,
            multiplier: multiplier,
            total_boosted_share: 0,
            acc_reward_per_share: 0,
            alloc_point: alloc_point,
            last_reward_timestamp: current_timestamp,
        });
        vector::push_back<TypeInfo>(&mut existing_lp_info.lp_list, type_info::type_of<CoinType>());
    }

    /// Set the existing pool
    public entry fun set<CoinType>(
        admin: &signer,
        alloc_point: u128,
        multiplier: u64,
        fee: u64,
    ) acquires MasterChefData, PoolInfo {
        let masterchef_data = borrow_global_mut<MasterChefData>(DEPLOYER_ADDRESS);

        assert!(signer::address_of(admin) == masterchef_data.admin_address, ERR_FORBIDDEN);
        assert!(exists<PoolInfo<CoinType>>(RESOURCE_ACCOUNT_ADDRESS), ERR_POOL_NOT_EXIST);

        let pool_info = borrow_global_mut<PoolInfo<CoinType>>(RESOURCE_ACCOUNT_ADDRESS);
        masterchef_data.total_alloc_point = masterchef_data.total_alloc_point - pool_info.alloc_point + alloc_point;
        pool_info.alloc_point = alloc_point;
        pool_info.multiplier = multiplier;
        pool_info.fee = fee;
    }

    /// Withdraw dev fee
    public entry fun withdraw_dev_fee<CoinType>(dev_account: &signer) acquires MasterChefData {
        let masterchef_data = borrow_global_mut<MasterChefData>(DEPLOYER_ADDRESS);
        assert!(signer::address_of(dev_account) == masterchef_data.dev_address, ERR_FORBIDDEN);

        let resource_account_signer = get_resource_account_signer();
        let coins_out = coin::withdraw<CoinType>(&resource_account_signer, coin::balance<CoinType>(RESOURCE_ACCOUNT_ADDRESS));
        if (!coin::is_account_registered<CoinType>(signer::address_of(dev_account))) {
            coin::register<CoinType>(dev_account);
        };
        coin::deposit<CoinType>(signer::address_of(dev_account), coins_out);
    }

    /// Withdraw the reward token for team
    public entry fun withdraw_for_team(team_account: &signer) acquires MasterChefData {
        let resource_account_signer = get_resource_account_signer();
        let masterchef_data = borrow_global_mut<MasterChefData>(DEPLOYER_ADDRESS);
        assert!(signer::address_of(team_account) == masterchef_data.team_address, ERR_FORBIDDEN);

        let coins_out = coin::withdraw<SUCKR>(&resource_account_signer, masterchef_data.pending_team_reward_token_amount);
        if (!coin::is_account_registered<SUCKR>(signer::address_of(team_account))) {
            coin::register<SUCKR>(team_account);
        };
        coin::deposit<SUCKR>(signer::address_of(team_account), coins_out);
        masterchef_data.pending_team_reward_token_amount = 0;
    }

    /// Withdraw the reward token for marketing
    public entry fun withdraw_for_marketing(marketing_account: &signer) acquires MasterChefData {
        let resource_account_signer = get_resource_account_signer();
        let masterchef_data = borrow_global_mut<MasterChefData>(DEPLOYER_ADDRESS);
        assert!(signer::address_of(marketing_account) == masterchef_data.marketing_address, ERR_FORBIDDEN);

        let coins_out = coin::withdraw<SUCKR>(&resource_account_signer, masterchef_data.pending_marketing_reward_token_amount);
        if (!coin::is_account_registered<SUCKR>(signer::address_of(marketing_account))) {
            coin::register<SUCKR>(marketing_account);
        };
        coin::deposit<SUCKR>(signer::address_of(marketing_account), coins_out);
        masterchef_data.pending_marketing_reward_token_amount = 0;
    }

    /// Withdraw the reward token for lottery
    public entry fun withdraw_for_lottery(lottery_account: &signer) acquires MasterChefData {
        let resource_account_signer = get_resource_account_signer();
        let masterchef_data = borrow_global_mut<MasterChefData>(DEPLOYER_ADDRESS);
        assert!(signer::address_of(lottery_account) == masterchef_data.lottery_address, ERR_FORBIDDEN);

        let coins_out = coin::withdraw<SUCKR>(&resource_account_signer, masterchef_data.pending_lottery_reward_token_amount);
        if (!coin::is_account_registered<SUCKR>(signer::address_of(lottery_account))) {
            coin::register<SUCKR>(lottery_account);
        };
        coin::deposit<SUCKR>(signer::address_of(lottery_account), coins_out);
        masterchef_data.pending_lottery_reward_token_amount = 0;
    }

    /// Withdraw the reward token for burn
    public entry fun withdraw_for_burn(burn_account: &signer) acquires MasterChefData {
        let resource_account_signer = get_resource_account_signer();
        let masterchef_data = borrow_global_mut<MasterChefData>(DEPLOYER_ADDRESS);
        assert!(signer::address_of(burn_account) == masterchef_data.burn_address, ERR_FORBIDDEN);

        let coins_out = coin::withdraw<SUCKR>(&resource_account_signer, masterchef_data.pending_burn_reward_token_amount);
        if (!coin::is_account_registered<SUCKR>(signer::address_of(burn_account))) {
            coin::register<SUCKR>(burn_account);
        };
        coin::deposit<SUCKR>(signer::address_of(burn_account), coins_out);
        masterchef_data.pending_burn_reward_token_amount = 0;
    }

/// functions list for every user ///
    /// Deposit LP tokens to pool
    public entry fun deposit<CoinType>(
        user_account: &signer,
        amount: u64
    ) acquires MasterChefData, UserInfo, PoolInfo, Events {
        update_pool<CoinType>();
        mint_reward_token();
        let resource_account_signer = get_resource_account_signer();
        settle_pending_reward<CoinType>(user_account);

        let pool_info = borrow_global_mut<PoolInfo<CoinType>>(RESOURCE_ACCOUNT_ADDRESS);
        let multiplier = get_boost_multiplier(pool_info.multiplier);
        let user_addr = signer::address_of(user_account);
        if (amount > 0) {
            let coins_in = coin::withdraw<CoinType>(user_account, amount);
            let amount_in = coin::value(&coins_in);
            amount_in = amount_in - amount_in * pool_info.fee / PERCENT_PRECISION;
            if (!coin::is_account_registered<CoinType>(RESOURCE_ACCOUNT_ADDRESS)) {
                coin::register<CoinType>(&resource_account_signer);
            };
            coin::deposit<CoinType>(RESOURCE_ACCOUNT_ADDRESS, coins_in);

            if (!exists<UserInfo<CoinType>>(user_addr)) {
                move_to(user_account, UserInfo<CoinType>{
                    amount: amount_in,
                    reward_debt: 0,
                    paid_reward_token_amount: 0,
                });
            } else {
                let user_info = borrow_global_mut<UserInfo<CoinType>>(user_addr);
                user_info.amount = user_info.amount + amount_in;
            };
            pool_info.total_boosted_share = pool_info.total_boosted_share + (amount_in as u128) * multiplier / (PERCENT_PRECISION as u128);
        };

        let user_info = borrow_global_mut<UserInfo<CoinType>>(user_addr);
        user_info.reward_debt = (user_info.amount as u128) * pool_info.acc_reward_per_share / ACC_REWARD_PRECISION;
        user_info.reward_debt = user_info.reward_debt * multiplier / (PERCENT_PRECISION as u128);

        let events = borrow_global_mut<Events>(RESOURCE_ACCOUNT_ADDRESS);
        event::emit_event(&mut events.deposit_event, DepositEvent {
            coin_type: type_info::type_of<CoinType>(),
            amount: amount,
        });
    }

    /// Withdraw LP tokens from pool
    public entry fun withdraw<CoinType>(
        user_account: &signer,
        amount_out: u64
    ) acquires MasterChefData, UserInfo, PoolInfo, Events {
        update_pool<CoinType>();
        mint_reward_token();
        settle_pending_reward<CoinType>(user_account);

        let user_addr = signer::address_of(user_account);
        let pool_info = borrow_global_mut<PoolInfo<CoinType>>(RESOURCE_ACCOUNT_ADDRESS);
        let user_info = borrow_global_mut<UserInfo<CoinType>>(user_addr);
        let multiplier = get_boost_multiplier(pool_info.multiplier);
        assert!(user_info.amount >= amount_out, ERR_INSUFFICIENT_BALANCE);

        if (amount_out > 0) {
            user_info.amount = user_info.amount - amount_out;
            let resource_account_signer = get_resource_account_signer();
            let coins_out = coin::withdraw<CoinType>(&resource_account_signer, amount_out);
            coin::deposit<CoinType>(user_addr, coins_out);
        };
        user_info.reward_debt = (user_info.amount as u128) * pool_info.acc_reward_per_share / ACC_REWARD_PRECISION;
        user_info.reward_debt = user_info.reward_debt * multiplier / (PERCENT_PRECISION as u128);
        pool_info.total_boosted_share = pool_info.total_boosted_share - (amount_out as u128) * multiplier / (PERCENT_PRECISION as u128);

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
        
        let pool_info = borrow_global_mut<PoolInfo<CoinType>>(RESOURCE_ACCOUNT_ADDRESS);
        let multiplier = get_boost_multiplier(pool_info.multiplier);
        let user_info = borrow_global_mut<UserInfo<CoinType>>(user_addr);
        let amount_out = user_info.amount;
        let boosted_amount = (amount_out as u128) * multiplier / (PERCENT_PRECISION as u128);
        assert!(amount_out > 0, ERR_MUST_BE_GREATER_THAN_ZERO);

        user_info.amount = 0;
        user_info.reward_debt = 0;
        pool_info.total_boosted_share = pool_info.total_boosted_share - boosted_amount;
        let resource_account_signer = get_resource_account_signer();
        let coins_out = coin::withdraw<CoinType>(&resource_account_signer, amount_out);
        coin::deposit<CoinType>(user_addr, coins_out);

        let events = borrow_global_mut<Events>(RESOURCE_ACCOUNT_ADDRESS);
        event::emit_event(&mut events.emergency_withdraw_event, WithdrawEvent {
            coin_type: type_info::type_of<CoinType>(),
            amount: amount_out,
        });
    }

    /// Update pool info
    public entry fun update_pool<CoinType>() acquires MasterChefData, PoolInfo {
        assert!(exists<PoolInfo<CoinType>>(RESOURCE_ACCOUNT_ADDRESS), ERR_POOL_NOT_EXIST);

        let current_timestamp = timestamp::now_seconds();
        let pool_info = borrow_global_mut<PoolInfo<CoinType>>(RESOURCE_ACCOUNT_ADDRESS);
        if (current_timestamp > pool_info.last_reward_timestamp) {
            let masterchef_data = borrow_global<MasterChefData>(DEPLOYER_ADDRESS);
            
            if (masterchef_data.total_alloc_point > 0 && pool_info.total_boosted_share > 0) {
                let multiplier = current_timestamp - pool_info.last_reward_timestamp;
                let reward_amount = (multiplier as u128) * masterchef_data.per_second_reward * pool_info.alloc_point / masterchef_data.total_alloc_point;
                reward_amount = reward_amount * (masterchef_data.farming_percent as u128) / (PERCENT_PRECISION as u128);
                pool_info.acc_reward_per_share = pool_info.acc_reward_per_share + reward_amount * ACC_REWARD_PRECISION / (pool_info.total_boosted_share as u128);
            };
            pool_info.last_reward_timestamp = current_timestamp;
        }
    }

/// function list for private
    /// Transfer pending reward token to user
    fun settle_pending_reward<CoinType>(
        user_account: &signer
    ) acquires MasterChefData, UserInfo, PoolInfo {
        let user_addr = signer::address_of(user_account);
        if (exists<UserInfo<CoinType>>(user_addr)) {
            let user_info = borrow_global_mut<UserInfo<CoinType>>(user_addr);
            if (user_info.amount > 0) {
                let pool_info = borrow_global_mut<PoolInfo<CoinType>>(RESOURCE_ACCOUNT_ADDRESS);
                let multiplier = get_boost_multiplier(pool_info.multiplier);
                let pending_amount = (user_info.amount as u128) * pool_info.acc_reward_per_share / ACC_REWARD_PRECISION;
                pending_amount = pending_amount * multiplier / (PERCENT_PRECISION as u128);
                if (pending_amount > user_info.reward_debt && coin::balance<SUCKR>(RESOURCE_ACCOUNT_ADDRESS) >= (pending_amount as u64)) {
                    pending_amount = pending_amount - user_info.reward_debt;
                    let resource_account_signer = get_resource_account_signer();
                    let coins_out = coin::withdraw<SUCKR>(&resource_account_signer, (pending_amount as u64));
                    
                    if (!coin::is_account_registered<SUCKR>(user_addr)) {
                        coin::register<SUCKR>(user_account);
                    };
                    coin::deposit(user_addr, coins_out);
                    user_info.paid_reward_token_amount = user_info.paid_reward_token_amount + pending_amount;
                }
                
            }
        }
    }

    /// Mint the reward token
    public fun mint_reward_token() acquires MasterChefData {
        let resource_account_signer = get_resource_account_signer();
        let masterchef_data = borrow_global_mut<MasterChefData>(DEPLOYER_ADDRESS);
        let current_timestamp = timestamp::now_seconds();
        let new_mint_amount = (masterchef_data.per_second_reward as u64) * (current_timestamp - masterchef_data.last_timestamp_mint);
        
        masterchef_data.pending_team_reward_token_amount = masterchef_data.pending_team_reward_token_amount + new_mint_amount * masterchef_data.team_percent / PERCENT_PRECISION;
        masterchef_data.pending_burn_reward_token_amount = masterchef_data.pending_burn_reward_token_amount + new_mint_amount * masterchef_data.burn_percent / PERCENT_PRECISION;
        masterchef_data.pending_lottery_reward_token_amount = masterchef_data.pending_lottery_reward_token_amount + new_mint_amount * masterchef_data.lottery_percent / PERCENT_PRECISION;
        masterchef_data.pending_marketing_reward_token_amount = masterchef_data.pending_marketing_reward_token_amount + new_mint_amount * masterchef_data.marketing_percent / PERCENT_PRECISION;
        masterchef_data.last_timestamp_mint = current_timestamp;
        
        MosquitoCoin::mint_SUCKR(&resource_account_signer, new_mint_amount);
    }
}