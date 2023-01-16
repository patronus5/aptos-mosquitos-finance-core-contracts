module PresaleDeployer::Presale {
    use MasterChefDeployer::MosquitoCoin::{ SUCKR };
    use liquidswap::router_v2;
    use liquidswap::curves;
    use liquidswap::math;

    use std::signer;
    // use std::event;
    use std::vector;
    use std::type_info::{ Self, TypeInfo };
    use aptos_framework::timestamp;
    use aptos_framework::account::{ Self, SignerCapability };
    use aptos_framework::coin::{ Self, Coin };

    /// When coins is not sorted or not exist
    const ERR_INCORRECT_PAIR: u64 = 105;
    /// When user is not admin
    const ERR_FORBIDDEN: u64 = 106;
    /// When coin is not registered for payment mothod
    const ERR_NOT_EXIST: u64 = 107;
    /// When presale is not started 
    const ERR_NOT_STARTED: u64 = 108;
    /// When presale is ended 
    const ERR_ENDED: u64 = 109;
    /// When presale is already started 
    const ERR_ALREADY_STARTED: u64 = 110;
    /// When the value is less than certain value
    const ERR_MUST_BE_GREATER: u64 = 111;
    /// When 2 coins already registered
    const ERR_ALREADY_REGISTERED: u64 = 112;

    const DEPLOYER_ADDRESS: address = @PresaleDeployer;
    const RESOURCE_ACCOUNT_ADDRESS: address = @PresaleResourceAccount;

    struct CoinInfo has drop, store {
        coin_type: TypeInfo,
        stable: bool
    }

    struct UserInfo has drop, store {
        addr: address,
        paid_coin_x_amount: u64,
        paid_coin_y_amount: u64,
        reserved_amount: u64
    }

    struct PresaleData has key {
        signer_cap: SignerCapability,
        admin_addr: address,
        token_price: u64,
        coin_vec: vector<CoinInfo>,
        user_vec: vector<UserInfo>,
        treasury: Coin<SUCKR>,
        is_presale_available: bool,
        end_timestamp: u64,
    }

    public entry fun initialize(admin: &signer) {
        let (_, signer_cap) = account::create_resource_account(admin, x"30");
        let resource_account_signer = account::create_signer_with_capability(&signer_cap);

        move_to(&resource_account_signer, PresaleData {
            signer_cap: signer_cap,
            admin_addr: signer::address_of(admin),
            token_price: 50000,
            coin_vec: vector::empty(),
            user_vec: vector::empty(),
            treasury: coin::zero(),
            is_presale_available: false,
            end_timestamp: 0
        });
    }

    public fun get_resource_address(): address acquires PresaleData {
        let resource_account_signer = get_resource_account_signer();
        signer::address_of(&resource_account_signer)
    }

    // Return resource account signer
    fun get_resource_account_signer(): signer acquires PresaleData {
        let signer_cap = &borrow_global<PresaleData>(RESOURCE_ACCOUNT_ADDRESS).signer_cap;
        account::create_signer_with_capability(signer_cap)
    }

    // Enable the presale and set the end time.
    public entry fun start_presale(admin: &signer) acquires PresaleData {
        let current_timestamp = timestamp::now_seconds();
        let presale_data = borrow_global_mut<PresaleData>(RESOURCE_ACCOUNT_ADDRESS);
        assert!(signer::address_of(admin) == presale_data.admin_addr, ERR_FORBIDDEN);

        presale_data.is_presale_available = true;
        presale_data.end_timestamp = current_timestamp;
    }

    // Register coin X, Y for payment method.
    public entry fun register_coin<X, Y>(
        admin: &signer
    ) acquires PresaleData {
        let presale_data = borrow_global_mut<PresaleData>(RESOURCE_ACCOUNT_ADDRESS);
        assert!(vector::length(&presale_data.coin_vec) < 2, ERR_ALREADY_REGISTERED);
        assert!(signer::address_of(admin) == presale_data.admin_addr, ERR_FORBIDDEN);

        vector::push_back<CoinInfo>(&mut presale_data.coin_vec, CoinInfo {
            coin_type: type_info::type_of<X>(),
            stable: false,
        });
        vector::push_back<CoinInfo>(&mut presale_data.coin_vec, CoinInfo {
            coin_type: type_info::type_of<Y>(),
            stable: true,
        });
    }

    // Check the X, Y is registered, and get the id
    public fun is_registered_coin<X, Y>(): (u64, u64) acquires PresaleData {
        let presale_data = borrow_global_mut<PresaleData>(RESOURCE_ACCOUNT_ADDRESS);
        let x_coin_type = type_info::type_of<X>();
        let y_coin_type = type_info::type_of<Y>();
        
        // Check X, Y is registerd or not.
        let i = 0;
        let x_index = 2;
        let y_index = 2;
        let len = vector::length(&presale_data.coin_vec);
        while (i < len) {
            let coin_info = vector::borrow<CoinInfo>(&presale_data.coin_vec, i);
            if (coin_info.coin_type == x_coin_type) {
                x_index = i
            };
            if (coin_info.coin_type == y_coin_type) {
                y_index = i
            };
            i = i + 1;
        };

        (x_index, y_index)
    }

    // Buy the SUCKR token using X coin
    public entry fun buy_SUCKR<X, Y>(
        user_account: &signer,
        amount: u64
    ) acquires PresaleData {
        assert!(amount > 0, ERR_MUST_BE_GREATER);

        // Check X, Y is registerd or not.
        let x_scale = math::pow_10(coin::decimals<X>());
        let (x_index, y_index) = is_registered_coin<X, Y>();
        assert!(x_index != y_index, ERR_NOT_EXIST);
        assert!(x_index < 2 && y_index < 2, ERR_NOT_EXIST);

        let resource_account_signer = get_resource_account_signer();
        let presale_data = borrow_global_mut<PresaleData>(RESOURCE_ACCOUNT_ADDRESS);

        // Check the presale is availabe or not
        let current_timestamp = timestamp::now_seconds();
        assert!(presale_data.is_presale_available, ERR_NOT_STARTED);
        assert!(presale_data.end_timestamp > current_timestamp, ERR_ENDED);

        // Assume that user want to buy the SUCKR with SUDT in default.
        let coin_amount: u128 = (presale_data.token_price as u128) * (amount as u128);
        // When user want to buy the SUCKR with aptos_coin
        if (x_index == 0) {
            let aptos_amount = router_v2::get_amount_out<X, Y, curves::Uncorrelated>(
                presale_data.token_price
            );
            coin_amount = (aptos_amount as u128) * (amount as u128);
        };
        coin_amount = coin_amount / (x_scale as u128);

        // Transfer user coin to resource account
        let coins_in = coin::withdraw<X>(user_account, (coin_amount as u64));
        if (!coin::is_account_registered<X>(RESOURCE_ACCOUNT_ADDRESS)) {
            coin::register<X>(&resource_account_signer);
        };
        coin::deposit<X>(RESOURCE_ACCOUNT_ADDRESS, coins_in);

        let paid_coin_x_amount = 0;
        let paid_coin_y_amount = 0;
        if (x_index == 0) {
            paid_coin_x_amount = (coin_amount as u64);
        } else {
            paid_coin_y_amount = (coin_amount as u64);
        };
        
        if (!coin::is_account_registered<SUCKR>(signer::address_of(user_account))) {
            coin::register<SUCKR>(user_account);
        };
        vector::push_back<UserInfo>(&mut presale_data.user_vec, UserInfo {
            paid_coin_x_amount,
            paid_coin_y_amount,
            addr: signer::address_of(user_account),
            reserved_amount: amount,
        });
    }

    // Release the pending SUCKR for users
    public entry fun release_SUCKR(admin: &signer) acquires PresaleData {
        let presale_data = borrow_global_mut<PresaleData>(RESOURCE_ACCOUNT_ADDRESS);
        assert!(signer::address_of(admin) == presale_data.admin_addr, ERR_FORBIDDEN);
        
        // Check the presale is availabe or not
        let current_timestamp = timestamp::now_seconds();
        assert!(presale_data.is_presale_available, ERR_NOT_STARTED);
        assert!(presale_data.end_timestamp < current_timestamp, ERR_ENDED);

        let i = 0;
        let len = vector::length(&mut presale_data.user_vec);
        while (i < len) {
            let user_info = vector::borrow<UserInfo>(&presale_data.user_vec, i);
            // Transfer the SUCKR token to user account
            let coins_out = coin::extract(&mut presale_data.treasury, user_info.reserved_amount);
            coin::deposit<SUCKR>(user_info.addr, coins_out);
            i = i + 1;
        };
    }

    // Refunds the paid aptos_coin and USDT to users
    public entry fun refund_to_users<X, Y>(admin: &signer) acquires PresaleData {
        let (x_index, y_index) = is_registered_coin<X, Y>();
        assert!(x_index == 0 && y_index == 1, ERR_INCORRECT_PAIR);
        
        let resource_account_signer = get_resource_account_signer();
        let presale_data = borrow_global_mut<PresaleData>(RESOURCE_ACCOUNT_ADDRESS);
        assert!(signer::address_of(admin) == presale_data.admin_addr, ERR_FORBIDDEN);

        // Check the presale is availabe or not
        let current_timestamp = timestamp::now_seconds();
        assert!(presale_data.is_presale_available, ERR_NOT_STARTED);
        assert!(presale_data.end_timestamp < current_timestamp, ERR_ENDED);

        let i = 0;
        let len = vector::length(&mut presale_data.user_vec);
        while (i < len) {
            let user_info = vector::borrow<UserInfo>(&presale_data.user_vec, i);
            let x_amount_out = if (user_info.paid_coin_x_amount < coin::balance<X>(RESOURCE_ACCOUNT_ADDRESS)) {
                user_info.paid_coin_x_amount
            } else {
                coin::balance<X>(RESOURCE_ACCOUNT_ADDRESS)
            };
            let y_amount_out = if (user_info.paid_coin_y_amount < coin::balance<Y>(RESOURCE_ACCOUNT_ADDRESS)) {
                user_info.paid_coin_y_amount
            } else {
                coin::balance<Y>(RESOURCE_ACCOUNT_ADDRESS)
            };

            let x_coins_out = coin::withdraw<X>(&resource_account_signer, x_amount_out);
            let y_coins_out = coin::withdraw<Y>(&resource_account_signer, y_amount_out);
            coin::deposit<X>(user_info.addr, x_coins_out);
            coin::deposit<Y>(user_info.addr, y_coins_out);
        };
    }
}
