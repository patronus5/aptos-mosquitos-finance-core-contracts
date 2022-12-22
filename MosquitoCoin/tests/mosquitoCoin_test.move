#[test_only]
module MasterChefDeployer::MosquitosCoinTests {
    #[test_only]
    use std::signer;
    #[test_only]
    use std::debug;
    #[test_only]
    use aptos_framework::genesis;
    #[test_only]
    use aptos_framework::account::create_account_for_test;
    #[test_only]
    use aptos_framework::coin::{
        Self
    };

    #[test_only]
    use MasterChefDeployer::MosquitoCoin::{ Self, SUCKR };

    #[test_only]
    const INIT_FAUCET_COIN:u64 = 23862;

    #[test_only]
    public entry fun test_module_init(admin: &signer) {
        MosquitoCoin::initialize(admin);
    }

    #[test(admin = @MasterChefDeployer, resource_account = @ResourceAccountDeployer)]
    public entry fun test_mint_coin(admin: &signer, resource_account: &signer) {
        genesis::setup();
        create_account_for_test(signer::address_of(admin));
        create_account_for_test(signer::address_of(resource_account));
        test_module_init(admin);
        MosquitoCoin::mint_SUCKR(resource_account, INIT_FAUCET_COIN);
        let cur_user_balance = coin::balance<SUCKR>(signer::address_of(resource_account));
        debug::print(&cur_user_balance);

        MosquitoCoin::register_SUCKR(admin);
        MosquitoCoin::burn_SUCKR(resource_account, 120);
        let coins = coin::withdraw<SUCKR>(resource_account, 862);
        coin::deposit<SUCKR>(signer::address_of(admin), coins);
        cur_user_balance = coin::balance<SUCKR>(signer::address_of(resource_account));
        debug::print(&cur_user_balance);
    }
}