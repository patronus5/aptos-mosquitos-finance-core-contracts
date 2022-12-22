#[test_only]
module MasterChefDeployer::MasterChefTests {
    #[test_only]
    use std::signer;
    // use std::type_info::{ Self, TypeInfo };
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
        MasterChef::initialize(admin);
        let resource_account_address = MasterChef::get_resource_address();
        debug::print(&resource_account_address);
    }

    #[test_only]
    public entry fun test_coin_init(admin: &signer, someone: &signer) {
        genesis::setup();
        create_account_for_test(signer::address_of(admin));
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
    
            MasterChef::add<BTC>(admin, 30, 1, 20);
            MasterChef::add<USDT>(admin, 50, 1, 15);
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

    // #[test(admin = @MasterChefDeployer)]
    // public entry fun test_add_pool(admin: &signer) {
    //     test_module_init(admin);
    //     MasterChef::add<USDT>(admin, 30);
    // }

    // #[test(user_account = @MasterChefDeployer)]
    // public entry fun test_set_pool(user_account: signer) {
    //     test_module_init(&user_account);
    //     MasterChef::add<BTC>(&user_account, 30);
    //     MasterChef::set<BTC>(&user_account, 50);
    // }

    #[test(admin = @MasterChefDeployer, resource_account = @ResourceAccountDeployer, someone = @0x11)]
    public entry fun test_deposit_and_withdraw(admin: &signer, resource_account: &signer, someone: &signer) {
        test_module_init(admin);
        test_coin_init(admin, someone);

        let pre_user_balance = coin::balance<BTC>(signer::address_of(someone));
        debug::print(&pre_user_balance);
        MasterChef::deposit<BTC>(someone, 50);
        let cur_user_balance = coin::balance<BTC>(signer::address_of(someone));
        debug::print(&cur_user_balance);
        let btc_pool_balance = coin::balance<BTC>(signer::address_of(resource_account));
        debug::print(&btc_pool_balance);
        let btc_pool_TC_balance = coin::balance<MasterChef::TestCoin>(signer::address_of(resource_account));
        debug::print(&btc_pool_TC_balance);

        MasterChef::withdraw<BTC>(someone, 27);
        cur_user_balance = coin::balance<BTC>(signer::address_of(someone));
        debug::print(&cur_user_balance);
        btc_pool_balance = coin::balance<BTC>(signer::address_of(resource_account));
        debug::print(&btc_pool_balance);
        btc_pool_TC_balance = coin::balance<MasterChef::TestCoin>(signer::address_of(resource_account));
        debug::print(&btc_pool_TC_balance);
    }

    #[test(admin = @MasterChefDeployer, resource_account = @ResourceAccountDeployer, someone = @0x11)]
    public entry fun test_mint_reward_token(admin: &signer, resource_account: &signer, someone: &signer) {
        test_module_init(admin);
        test_coin_init(admin, someone);

        let btc_pool_TC_balance = coin::balance<MasterChef::TestCoin>(signer::address_of(resource_account));
        debug::print(&btc_pool_TC_balance);
        MasterChef::mint_reward_token();
        btc_pool_TC_balance = coin::balance<MasterChef::TestCoin>(signer::address_of(resource_account));
        debug::print(&btc_pool_TC_balance);
    }
}