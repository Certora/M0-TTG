// SPDX-License-Identifier: GLP-3.0
pragma solidity 0.8.17;

interface IList {
    function add(address _address) external;

    function remove(address _address) external;

    function contains(address _address) external view returns (bool);

    function changeAdmin(address _newAdmin) external;
}