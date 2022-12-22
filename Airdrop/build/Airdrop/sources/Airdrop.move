module AirdropDeployer::Airdrop {
    use MasterChefDeployer::MosquitoCoin::{ Self, SUCKR };
    use std::signer;
    use std::event;
    use std::vector;
    use std::simple_map::{ Self, SimpleMap };
    // use aptos_framework::timestamp;
    use aptos_framework::account;
    use aptos_framework::coin::{ Self, Coin };

    /// When insufficient balance
    const ERR_INSUFFICIENT_BALANCE: u64 = 105;
    /// When user is not admin
    const ERR_FORBIDDEN: u64 = 106;
    /// When user is not in whitelist
    const ERR_NOT_EXIST: u64 = 107;

    const DEPLOYER_ADDRESS: address = @AirdropDeployer;

    // struct SUCKR {}

    struct Airdrop has key {
        admin_address: address,
        map: SimpleMap<address, u64>,
        treasury: Coin<SUCKR>,
        claim_airdrop_event: event::EventHandle<ClaimAirdropEvent>,
    }

    struct ClaimAirdropEvent has drop, store {
        addr: address,
        value: u64,
    }

    public entry fun initialize(admin: &signer) {
        let total_amount = coin::balance<SUCKR>(signer::address_of(admin));
        let coins = coin::withdraw<SUCKR>(admin, total_amount);
        move_to(admin, Airdrop {
            admin_address: signer::address_of(admin),
            map: simple_map::create<address, u64>(),
            treasury: coins,
            claim_airdrop_event: account::new_event_handle<ClaimAirdropEvent>(admin),
        });
    }

    public entry fun add_airdrop_list(
        admin: &signer,
        address_list: vector<address>,
        amount_list: vector<u64>
    ) acquires Airdrop {
        let i:u64 = 0;
        let len = vector::length(&address_list);
        let airdrop_data = borrow_global_mut<Airdrop>(DEPLOYER_ADDRESS);
        assert!(signer::address_of(admin) == airdrop_data.admin_address, ERR_FORBIDDEN);
        while (i < len) {
            let addr = vector::borrow<address>(&address_list, i);
            let amount = vector::borrow<u64>(&amount_list, i);
            simple_map::add<address, u64>(&mut airdrop_data.map, *addr, *amount);
            i = i + 1;
        };
    }

    public entry fun add_custom_airdrop_test_only(
        admin: &signer,
        user_addr: address,
        user_amount: u64
    ) acquires Airdrop {
        let airdrop_data = borrow_global_mut<Airdrop>(DEPLOYER_ADDRESS);
        assert!(signer::address_of(admin) == airdrop_data.admin_address, ERR_FORBIDDEN);
        simple_map::add<address, u64>(&mut airdrop_data.map, user_addr, user_amount);
    }

    public entry fun claim_airdrop(account: &signer) acquires Airdrop {
        let airdrop_data = borrow_global_mut<Airdrop>(DEPLOYER_ADDRESS);
        let user_addr = signer::address_of(account);
        assert!(simple_map::contains_key<address, u64>(&airdrop_data.map, &user_addr), ERR_NOT_EXIST);
        let amount = *(simple_map::borrow<address, u64>(&airdrop_data.map, &user_addr));
        let total_amount = (coin::value(&airdrop_data.treasury) as u64);
        assert!(total_amount >= amount, ERR_INSUFFICIENT_BALANCE);

        if (!coin::is_account_registered<SUCKR>(user_addr)) {
            coin::register<SUCKR>(account);
        };
        let coins = coin::extract(&mut airdrop_data.treasury, amount);
        coin::deposit(user_addr, coins);
        event::emit_event(&mut airdrop_data.claim_airdrop_event, ClaimAirdropEvent {
            addr: user_addr,
            value: amount,
        })
    }

    public entry fun burn_unclaimed_airdrop(admin: &signer) acquires Airdrop {
        let airdrop_data = borrow_global_mut<Airdrop>(DEPLOYER_ADDRESS);
        assert!(signer::address_of(admin) == airdrop_data.admin_address, ERR_FORBIDDEN);
        let amount = (coin::value(&airdrop_data.treasury) as u64);
        let coins = coin::extract(&mut airdrop_data.treasury, amount);
        coin::deposit(signer::address_of(admin), coins);
        MosquitoCoin::burn_SUCKR(admin, amount);
    }
}
