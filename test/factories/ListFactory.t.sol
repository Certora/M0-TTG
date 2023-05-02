// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import {IList} from "src/interfaces/IList.sol";
import {ListFactory} from "src/factories/ListFactory.sol";
import {SPOG_Base} from "test/shared/SPOG_Base.t.sol";

contract ListFactoryTest is SPOG_Base {
    function test_listDeployWithFactory() public {
        ListFactory listFactory = new ListFactory();

        address item1 = createUser("item1");

        address[] memory items = new address[](1);
        items[0] = item1;

        IList list = listFactory.deploy(address(spog), "List Name", items, 0);

        assertTrue(list.contains(item1), "item1 should be in the list");
        assertTrue(list.admin() == address(spog), "spog should be the admin");
    }

    function test_predictAddress() public {
        ListFactory listFactory = new ListFactory();

        address item1 = createUser("item1");

        address[] memory items = new address[](1);
        items[0] = item1;

        IList list = listFactory.deploy(address(spog), "List Name", items, 0);

        bytes memory bytecode = listFactory.getBytecode("List Name");

        address listAddress = listFactory.predictListAddress(bytecode, 0);

        assertTrue(listAddress != address(0), "listAddress should not be 0x0");
        assertTrue(listAddress == address(list), "listAddress should be the same as the list address");
    }

    function test_fallback() public {
        ListFactory factory = new ListFactory();

        vm.expectRevert("ListFactory: non-existent function");
        (bool success,) = address(factory).call(abi.encodeWithSignature("doesNotExist()"));

        assertEq(success, true);
    }
}