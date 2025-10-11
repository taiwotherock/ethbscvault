// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/**
 * @title AccessControlModule
 * @notice OpenZeppelin-compatible access control module with multisig governance.
 * @dev Compatible with Base, Polygon, BNB Chain and other EVM networks.
 *      Gas-efficient bitmask implementation while emitting OZ-standard events.
 */
contract AccessControlModule {
    // ===== Role Identifiers =====
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant CREDIT_OFFICER_ROLE = keccak256("CREDIT_OFFICER_ROLE");
    bytes32 public constant KEEPER_ROLE = keccak256("KEEPER_ROLE");
    bytes32 public constant OTC_TRADER = keccak256("OTC_TRADER");

    address public multisig;

    // Role bit flags (gas-efficient)
    uint8 private constant _BIT_ADMIN  = 1 << 0;
    uint8 private constant _BIT_CREDIT = 1 << 1;
    uint8 private constant _BIT_KEEPER = 1 << 2;
    uint8 private constant _BIT_TRADER = 1 << 3;

    mapping(address => uint8) private _roles;

    // ===== OpenZeppelin-Compatible Events =====
    event RoleAdminChanged(bytes32 indexed role, bytes32 indexed previousAdminRole, bytes32 indexed newAdminRole);
    event RoleGranted(bytes32 indexed role, address indexed account, address indexed sender);
    event RoleRevoked(bytes32 indexed role, address indexed account, address indexed sender);
    event MultisigUpdated(address indexed newMultisig);

    modifier onlyRole(bytes32 role) {
        require(hasRole(role, msg.sender) || msg.sender == multisig, "AccessControl: insufficient permissions");
        _;
    }

    constructor(address _initialAdmin, address _multisig) {
        require(_initialAdmin != address(0) && _multisig != address(0), "Invalid address");

        // grant ADMIN_ROLE to _initialAdmin
        _roles[_initialAdmin] = _BIT_ADMIN;
        multisig = _multisig;

        emit RoleGranted(ADMIN_ROLE, _initialAdmin, msg.sender);
        emit MultisigUpdated(_multisig);
    }

    // ===== Grant & Revoke Roles =====

    function grantRole(bytes32 role, address account) external onlyRole(ADMIN_ROLE) {
        _grantRole(role, account);
    }

    function revokeRole(bytes32 role, address account) external onlyRole(ADMIN_ROLE) {
        _revokeRole(role, account);
    }

    function renounceRole(bytes32 role) external {
        _revokeRole(role, msg.sender);
    }

    // ===== Role Checks =====

    function hasRole(bytes32 role, address account) public view returns (bool) {
        uint8 flags = _roles[account];
        if (role == ADMIN_ROLE) return (flags & _BIT_ADMIN) != 0;
        if (role == CREDIT_OFFICER_ROLE) return (flags & _BIT_CREDIT) != 0;
        if (role == KEEPER_ROLE) return (flags & _BIT_KEEPER) != 0;
        return false;
    }

    function isAdmin(address account) public view returns (bool) {
        return hasRole(ADMIN_ROLE, account);
    }

    function isCreditOfficer(address account) public view returns (bool) {
        return hasRole(CREDIT_OFFICER_ROLE, account);
    }

    function isKeeper(address account) public view returns (bool) {
        return hasRole(KEEPER_ROLE, account);
    }

    function isTrader(address account) public view returns (bool) {
        return hasRole(OTC_TRADER, account);
    }

    // ===== Multisig Management =====

    function setMultisig(address newMultisig) external onlyRole(ADMIN_ROLE) {
        require(newMultisig != address(0), "Invalid address");
        multisig = newMultisig;
        emit MultisigUpdated(newMultisig);
    }

    // ===== Internal Logic =====

    function _grantRole(bytes32 role, address account) internal {
        require(account != address(0), "Invalid address");
        uint8 flag = _roleToBit(role);
        uint8 current = _roles[account];
        if ((current & flag) == 0) {
            _roles[account] = current | flag;
            emit RoleGranted(role, account, msg.sender);
        }
    }

    function _revokeRole(bytes32 role, address account) internal {
        require(account != address(0), "Invalid address");
        uint8 flag = _roleToBit(role);
        uint8 current = _roles[account];
        if ((current & flag) != 0) {
            _roles[account] = current & ~flag;
            emit RoleRevoked(role, account, msg.sender);
        }
    }

    function _roleToBit(bytes32 role) internal pure returns (uint8) {
        if (role == ADMIN_ROLE) return _BIT_ADMIN;
        if (role == CREDIT_OFFICER_ROLE) return _BIT_CREDIT;
        if (role == KEEPER_ROLE) return _BIT_KEEPER;
        if (role == OTC_TRADER) return _BIT_TRADER;
        revert("AccessControl: unknown role");
    }
}