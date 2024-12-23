#[cfg(test)]
mod tests {
    use dojo_cairo_test::WorldStorageTestTrait;
    use dojo::model::{ModelStorage, ModelValueStorage, ModelStorageTest};
    use dojo::world::WorldStorageTrait;
    use dojo_cairo_test::{
        spawn_test_world, NamespaceDef, TestResource, ContractDefTrait, ContractDef,
    };

    use starkludo::systems::game_actions::{
        GameActions, IGameActionsDispatcher, IGameActionsDispatcherTrait,
    };
    use starkludo::models::game::{Game, m_Game};
    use starkludo::models::player::{Player, m_Player};

    fn namespace_def() -> NamespaceDef {
        let ndef = NamespaceDef {
            namespace: "starkludo",
            resources: [
                TestResource::Model(m_Game::TEST_CLASS_HASH),
                TestResource::Model(m_Player::TEST_CLASS_HASH),
                TestResource::Contract(GameActions::TEST_CLASS_HASH),
                TestResource::Event(GameActions::e_GameCreated::TEST_CLASS_HASH),
            ]
                .span(),
        };

        ndef
    }

    fn contract_defs() -> Span<ContractDef> {
        [
            ContractDefTrait::new(@"starkludo", @"GameActions")
                .with_writer_of([dojo::utils::bytearray_hash(@"starkludo")].span())
        ]
            .span()
    }

    #[test]
    fn test_world() {
        let caller = starknet::contract_address_const::<'caller'>();

        let ndef = namespace_def();
        let mut world = spawn_test_world([ndef].span());
        world.sync_perms_and_inits(contract_defs());

        let (contract_address, _) = world.dns(@"GameActions").unwrap();
        let game_action_system = IGameActionsDispatcher { contract_address };
    }

    #[test]
    fn test_get_address_from_username() {
        let ndef = namespace_def();
        let mut world = spawn_test_world([ndef].span());
        world.sync_perms_and_inits(contract_defs());

        let (contract_address, _) = world.dns(@"GameActions").unwrap();
        let game_action_system = IGameActionsDispatcher { contract_address };

        let bob_address = starknet::contract_address_const::<'bob'>();
        let alice_address = starknet::contract_address_const::<'alice'>();
        let bob_username: felt252 = 'bob';
        let alice_username: felt252 = 'alice';

        let address_to_username1 = AddressToUsername {
            address: bob_address, username: bob_username,
        };
        let address_to_username2 = AddressToUsername {
            address: alice_address, username: alice_username,
        };

        world.write_model(@address_to_username1);
        world.write_model(@address_to_username2);

        let address_1 = game_action_system.get_address_from_username(bob_username);
        let address_2 = game_action_system.get_address_from_username(alice_username);

        assert(address_1 == bob_address, 'Wrong address 1');
        assert(address_2 == alice_address, 'Wrong address 2');

        let non_existent_address = starknet::contract_address_const::<'non_existent'>();
        let retrieved_username3 = game_action_system
            .get_username_from_address(non_existent_address);
        assert(retrieved_username3 == 0, 'Non-existent should return 0');
    }
}
