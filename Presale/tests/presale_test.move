#[test_only]
module PresaleDeployer::PresaleTests {
    #[test_only]
    use PresaleDeployer::Presale;

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
        MintCapability, FreezeCapability, BurnCapability
    };

    #[test_only]
    struct Aptos {}
    #[test_only]
    struct USDT {}
    #[test_only]
    struct Caps<phantom X> has key {
        mint: MintCapability<X>,
        freeze: FreezeCapability<X>,
        burn: BurnCapability<X>,
    }

    #[test_only]
    public entry fun test_module_init(admin: &signer) {
        genesis::setup();
        create_account_for_test(signer::address_of(admin));
        Presale::initialize(admin);
        let resource_account_address = Presale::get_resource_address();
        debug::print(&resource_account_address);
    }

    #[test(admin = @PresaleDeployer)]
    public entry fun test_register_coin(admin: &signer) {
        test_module_init(admin);

        // Presale::register_coin<Aptos>(admin, false);
        Presale::register_coin<USDT>(admin, true);

        Presale::buy_SUCKR<USDT>(admin, 20);
    }
}