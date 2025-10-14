// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @dev Lightweight reimplementation of OpenZeppelin's Initializable.
 * Allows initializer functions to be called only once.
 */
abstract contract Initializable {
    bool private _initialized;
    bool private _initializing;

    modifier initializer() {
        require(!_initialized || _initializing, "Initializable: already initialized");
        bool isTopLevel = !_initializing;
        if (isTopLevel) {
            _initializing = true;
            _initialized = true;
        }
        _;
        if (isTopLevel) {
            _initializing = false;
        }
    }

    modifier onlyInitializing() {
        require(_initializing, "Initializable: not initializing");
        _;
    }

    function _isInitialized() internal view returns (bool) {
        return _initialized;
    }
}