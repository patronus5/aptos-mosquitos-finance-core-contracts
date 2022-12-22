module MasterChefDeployer::MosquitoCoin {
    use std::signer;
    // use std::event;
    use std::string::utf8;
    use aptos_framework::coin::{
        Self, MintCapability, FreezeCapability, BurnCapability
    };
    // use aptos_framework::account::{ Self };

    /// When user is not admin
    const ERR_FORBIDDEN: u64 = 106;

    const DEPLOYER_ADDRESS: address = @MasterChefDeployer;
    const RESOURCE_ACCOUNT_ADDRESS: address = @ResourceAccountDeployer;

    /// Store min/burn/freeze capabilities for reward token under resource account
    struct Caps<phantom CoinType> has key {
        admin_address: address,
        direct_mint: bool,
        mint: MintCapability<CoinType>,
        freeze: FreezeCapability<CoinType>,
        burn: BurnCapability<CoinType>,
    }

    /// Reward coin structure
    struct SUCKR {}

    public entry fun initialize(admin: &signer) {
        let admin_addr = signer::address_of(admin);
        let (burn_cap, freeze_cap, mint_cap) = coin::initialize<SUCKR>(
            admin,
            utf8(b"MFI"),
            utf8(b"MFI"),
            8,
            true,
        );

        move_to(admin, Caps<SUCKR> {
            admin_address: admin_addr,
            direct_mint: false,
            mint: mint_cap,
            burn: burn_cap,
            freeze: freeze_cap,
        });
    }

    // Mints new coin on resource account
    public entry fun mint_SUCKR(admin: &signer, amount: u64) acquires Caps {
        let admin_addr = signer::address_of(admin);
        if (!coin::is_account_registered<SUCKR>(admin_addr)) {
            coin::register<SUCKR>(admin);
        };
        let caps = borrow_global<Caps<SUCKR>>(DEPLOYER_ADDRESS);
        assert!(admin_addr == RESOURCE_ACCOUNT_ADDRESS, ERR_FORBIDDEN);
        let coins = coin::mint<SUCKR>(amount, &caps.mint);
        coin::deposit(RESOURCE_ACCOUNT_ADDRESS, coins);
    }

    // Burn the coins on a account
    public entry fun burn_reward_token(
        user_account: &signer,
        amount: u64
    ) acquires Caps {
        let caps = borrow_global<Caps<SUCKR>>(DEPLOYER_ADDRESS);
        let burn_coins = coin::withdraw<SUCKR>(user_account, amount);
        coin::burn<SUCKR>(burn_coins, &caps.burn);
    }

    // only resource_account should call this
    public entry fun register_SUCKR(account: &signer) {
        let account_addr = signer::address_of(account);
        if (!coin::is_account_registered<SUCKR>(account_addr)) {
            coin::register<SUCKR>(account);
        };
    }
}
