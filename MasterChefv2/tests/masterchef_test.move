#[test_only]
module MasterChefDeployer::MasterChefTests {
    #[test_only]
    use std::signer;
    #[test_only]
    use std::string::utf8;
    #[test_only]
    use std::debug;
    #[test_only]
    use aptos_framework::genesis;
    #[test_only]
    use aptos_framework::account::create_account_for_test;
    // use aptos_framework::timestamp;
    #[test_only]
    use aptos_framework::coin::{
        Self, MintCapability, FreezeCapability, BurnCapability
    };
    // use aptos_framework::account::{ Self, SignerCapability };

    #[test_only]
    use MasterChefDeployer::MasterChef;
    #[test_only]
    use MasterChefDeployer::MosquitoCoin::{ Self };

    #[test_only]
    const INIT_FAUCET_COIN:u64 = 1000000000;

    #[test_only]
    struct Aptos {}
    #[test_only]
    struct BTC {}
    #[test_only]
    struct USDT {}
    #[test_only]
    struct TR {}
    #[test_only]
    struct Caps<phantom X> has key {
        mint: MintCapability<X>,
        freeze: FreezeCapability<X>,
        burn: BurnCapability<X>,
    }

    #[test_only]
    public entry fun test_module_init(admin: &signer) {
        // timestamp::update_global_time_for_test(100);
        genesis::setup();
        create_account_for_test(signer::address_of(admin));
        MosquitoCoin::initialize(admin);
        MasterChef::initialize(admin);
        let resource_account_address = MasterChef::get_resource_address();
        debug::print(&resource_account_address);
    }

    #[test_only]
    public entry fun test_coin_init(admin: &signer, someone: &signer, dev: &signer) {
        // genesis::setup();
        create_account_for_test(signer::address_of(dev));
        create_account_for_test(signer::address_of(someone));
        {
            let (burn_cap, freeze_cap, mint_cap) = coin::initialize<BTC>(
                admin,
                utf8(b"Bitcoin"),
                utf8(b"BTC"),
                6,
                true
            );
            coin::register<BTC>(someone);
            let coins = coin::mint<BTC>(INIT_FAUCET_COIN, &mint_cap);
            coin::deposit(signer::address_of(someone), coins);
    
            MasterChef::add<BTC>(admin, 30, 500);
            MasterChef::add<USDT>(admin, 50, 15);
            move_to(admin, Caps<BTC> {
                mint: mint_cap,
                freeze: freeze_cap,
                burn: burn_cap
            });
        }
    }

    #[test(admin = @MasterChefDeployer, another = @0x22)]
    public entry fun test_set_admin_address(admin: &signer, another: &signer) {
        test_module_init(admin);
        MasterChef::set_admin_address(admin, signer::address_of(another));
    }

    #[test(admin = @MasterChefDeployer, resource_account = @ResourceAccountDeployer, someone = @0x15, dev = @0x12)]
    public entry fun test_deposit_and_withdraw(
        admin: &signer,
        resource_account: &signer,
        someone: &signer,
        dev: &signer,
    ) {
        test_module_init(admin);
        test_coin_init(admin, someone, dev);

        coin::register<BTC>(resource_account);
        MasterChef::enable_farm(admin);

        // deposit
        let pre_user_balance = coin::balance<BTC>(signer::address_of(someone));
        debug::print(&pre_user_balance);
        MasterChef::deposit<BTC>(someone, 50);
        let cur_user_balance = coin::balance<BTC>(signer::address_of(someone));
        debug::print(&cur_user_balance);
        let btc_pool_balance = coin::balance<BTC>(signer::address_of(resource_account));
        debug::print(&btc_pool_balance);

        // withdraw
        MasterChef::emergency_withdraw<BTC>(someone);
        let cur_user_balance = coin::balance<BTC>(signer::address_of(someone));
        debug::print(&cur_user_balance);

        // MasterChef::set_dev_address(admin, signer::address_of(dev));
        // MasterChef::withdraw_dev_fee<BTC>(dev);
        // let dev_balance = coin::balance<BTC>(signer::address_of(dev));
        // debug::print(&dev_balance);
    }
}