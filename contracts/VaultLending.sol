// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;


interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
}

interface IAccessControlModule {
    function isAdmin(address account) external view returns (bool);
    function isCreditOfficer(address account) external view returns (bool);
}


contract VaultLending {

    struct Loan {
        bytes32 ref;
        address borrower;
        address token;
        address merchant;
        uint256 principal;
        uint256 outstanding;     // principal + remaining fee
        uint256 startedAt;
        uint256 installmentsPaid;
        uint256 fee;             // remaining fee
        uint256 totalPaid;       // total repaid (principal + fee)
        bool active;
    }

     // ====== Timelock ======
    struct Timelock {
        uint256 amount;
        address token;      // address(0) for ETH
        address to;
        uint256 unlockTime;
        bool executed;
    }


    uint256 private nextLoanId = 1;
     IAccessControlModule public immutable accessControl;
    bool public paused;
    uint256 private _locked;

    // Loan tracking
    mapping(bytes32 => Loan) public loans;
    mapping(address => bytes32[]) private borrowerLoans;
    mapping(bytes32 => uint256) private loanIndex;

    // Vault & pool tracking
    mapping(address => mapping(address => uint256)) public vault;            // vault[user][token]
    mapping(address => mapping(address => uint256)) public lenderContribution; // lender[token]
    mapping(address => uint256) public totalPoolContribution;               // total principal per token
    mapping(address => uint256) public pool;                                // total liquidity including fees

    // Fee tracking (optimized)
    mapping(address => uint256) public cumulativeFeePerToken;               // accumulated fee per 1 token deposited
    mapping(address => mapping(address => uint256)) public feeDebt;         // lender[token] = claimed portion
    uint256 constant FEE_PRECISION = 1e18;

    // Borrower & lender tracking
    mapping(address => bool) private isBorrower;
    address[] private borrowers;

    mapping(address => bool) private isLender;
    address[] private lenders;

    // Events
    event Deposit(address indexed user, address indexed token, uint256 amount);
    event Withdraw(address indexed user, address indexed token, uint256 amount);
    event LoanCreated(bytes32 loanId, address borrower, uint256 principal, uint256 fee);
    event LoanDisbursed(bytes32 loanId, address borrower, uint256 amount);
    event LoanRepaid(bytes32 loanId, address borrower, uint256 amount, uint256 feePaid);
    event LoanClosed(bytes32 loanId, address borrower);
    event FeesWithdrawn(address indexed lender, address indexed token, uint256 amount);

    event Paused();
    event Unpaused();
    event Whitelisted(address indexed user, bool status);
    event Blacklisted(address indexed user, bool status);
  
    event TimelockCreated(bytes32 indexed id, address token, address to, uint256 amount, uint256 unlockTime);
    event TimelockExecuted(bytes32 indexed id);

    mapping(address => bool) public whitelist;
    mapping(address => bool) public blacklist;


    constructor(address _accessControl) {
        require(_accessControl != address(0), "Invalid access control");
        accessControl = IAccessControlModule(_accessControl);
        _locked = 1;
    }

    // ====== Reentrancy Guard ======
    modifier nonReentrant() {
        require(_locked == 1, "ReentrancyGuard: reentrant call");
        _locked = 2;
        _;
        _locked = 1;
    }

    // ====== Modifiers ======
    modifier onlyAdmin() {
        require(accessControl.isAdmin(msg.sender), "Only admin");
        _;
    }

    modifier onlyCreditOfficer() {
        require(accessControl.isCreditOfficer(msg.sender), "Only credit officer");
        _;
    }

    modifier onlyWhitelisted(address user) {
        require(whitelist[user], "User not whitelisted");
        _;
    }

    modifier notBlacklisted(address user) {
        require(!blacklist[user], "User is blacklisted");
        _;
    }

    modifier loanExists(bytes32 ref) {
        require(loans[ref].borrower != address(0), "Loan does not exist");
        _;
    }

    modifier whenNotPaused() {
        require(!paused, "Contract paused");
        _;
    }

    // ====== Admin: Whitelist / Blacklist ======
    function setWhitelist(address user, bool status) external onlyAdmin {
        whitelist[user] = status;
        emit Whitelisted(user, status);
    }

    function setBlacklist(address user, bool status) external onlyAdmin {
        blacklist[user] = status;
        emit Blacklisted(user, status);
    }

    // ====== Admin: Pause / Unpause ======
    function pause() external onlyAdmin {
        paused = true;
        emit Paused();
    }

    function unpause() external onlyAdmin {
        paused = false;
        emit Unpaused();
    }

    /* ========== VAULT FUNCTIONS ========== */

    function depositToVault(address token, uint256 amount) external {
        require(amount > 0, "Amount must be > 0");
        IERC20(token).transferFrom(msg.sender, address(this), amount);

        // Update lender fee debt before increasing contribution
        feeDebt[msg.sender][token] += (amount * cumulativeFeePerToken[token]) / FEE_PRECISION;

        vault[msg.sender][token] += amount;
        lenderContribution[msg.sender][token] += amount;
        totalPoolContribution[token] += amount;
        pool[token] += amount;

        if (!isLender[msg.sender]) {
            lenders.push(msg.sender);
            isLender[msg.sender] = true;
        }

        emit Deposit(msg.sender, token, amount);
    }

    function withdrawFromVault(address token, uint256 amount) external 
    whenNotPaused notBlacklisted(msg.sender) onlyWhitelisted(msg.sender) {
        require(vault[msg.sender][token] >= amount, "Insufficient vault balance");

        // Update lender contribution and pool
        vault[msg.sender][token] -= amount;
        if (lenderContribution[msg.sender][token] >= amount) {
            lenderContribution[msg.sender][token] -= amount;
            totalPoolContribution[token] -= amount;
            pool[token] -= amount;
        }

         IERC20 tokenA = IERC20(token);
        //IERC20(token).transfer(msg.sender, amount);
        // Safe transfer with inline revert check
            (bool success, bytes memory data) = address(tokenA).call(
                abi.encodeWithSelector(tokenA.transfer.selector, msg.sender, amount)
            );

        emit Withdraw(msg.sender, token, amount);
    }

    /* ========== LOAN FUNCTIONS ========== */

    function createLoan(bytes32 ref,address token, address merchant, uint256 principal, uint256 fee)
     external onlyCreditOfficer {
        require(pool[token] >= principal, "Insufficient pool liquidity");

        
        Loan storage l = loans[ref];
        l.ref = ref;
        l.borrower = msg.sender;
        l.token = token;
        l.merchant = merchant;
        l.principal = principal;
        l.outstanding = principal + fee;
        l.startedAt = block.timestamp;
        l.installmentsPaid = 0;
        l.fee = fee;
        l.totalPaid = 0;
        l.active = true;


        // Track borrower
        loanIndex[ref] = borrowerLoans[msg.sender].length;
        borrowerLoans[msg.sender].push(ref);
        if (!isBorrower[msg.sender]) {
            borrowers.push(msg.sender);
            isBorrower[msg.sender] = true;
        }

        // Disburse principal to borrower vault
        pool[token] -= principal;
        vault[msg.sender][token] += principal;

        emit LoanCreated(ref, msg.sender, principal, fee);
        emit LoanDisbursed(ref, msg.sender, principal);
    }

    function repayLoan(bytes32 ref, uint256 amount) external {
        Loan storage loan = loans[ref];
        require(loan.active, "Loan is closed");
        require(loan.borrower == msg.sender, "Not borrower");
        require(amount > 0, "Amount must be > 0");

        uint256 remaining = amount;

        // Use vault balance first
        uint256 vaultBalance = vault[msg.sender][loan.token];
        if (vaultBalance > 0) {
            uint256 fromVault = vaultBalance >= remaining ? remaining : vaultBalance;
            vault[msg.sender][loan.token] -= fromVault;
            remaining -= fromVault;
        }

        // Use external transfer if needed
        if (remaining > 0) {
            IERC20(loan.token).transferFrom(msg.sender, address(this), remaining);
        }

        // Allocate fee portion
        uint256 feePaid = loan.fee >= amount ? amount : loan.fee;
        loan.fee -= feePaid;
        _addFeeToPool(loan.token, feePaid);

        uint256 principalPaid = amount - feePaid;
        if (principalPaid >= loan.outstanding) {
            principalPaid = loan.outstanding - feePaid;
        }

        loan.outstanding -= (principalPaid + feePaid);
        loan.totalPaid += amount;

        if (loan.outstanding == 0) {
            loan.active = false;
            _removeLoanFromBorrower(msg.sender, ref);
            emit LoanClosed(ref, msg.sender);
        }

        emit LoanRepaid(ref, msg.sender, principalPaid + feePaid, feePaid);
    }

    function _addFeeToPool(address token, uint256 feeAmount) internal {
        if (totalPoolContribution[token] == 0) return;
        cumulativeFeePerToken[token] += (feeAmount * FEE_PRECISION) / totalPoolContribution[token];
        pool[token] += feeAmount;
    }

    function _removeLoanFromBorrower(address borrower, bytes32 ref) internal {
        uint256 index = loanIndex[ref];
        bytes32 lastRef = borrowerLoans[borrower][borrowerLoans[borrower].length - 1];

        // Replace the removed ref with the last one
        borrowerLoans[borrower][index] = lastRef;
        loanIndex[lastRef] = index;

        // Remove last element and delete index mapping
        borrowerLoans[borrower].pop();
        delete loanIndex[ref];
    }

    /* ========== FEE WITHDRAWAL ========== */

    function getWithdrawableFees(address lender, address token) public view returns (uint256) {
        uint256 contribution = lenderContribution[lender][token];
        if (contribution == 0) return 0;

        uint256 accumulatedFee = (contribution * cumulativeFeePerToken[token]) / FEE_PRECISION;
        uint256 withdrawable = accumulatedFee > feeDebt[lender][token] ? accumulatedFee - feeDebt[lender][token] : 0;
        return withdrawable;
    }

    function withdrawFees(address token) external {
        uint256 amount = getWithdrawableFees(msg.sender, token);
        require(amount > 0, "No fees to withdraw");

        feeDebt[msg.sender][token] += amount;
        pool[token] -= amount;

        IERC20(token).transfer(msg.sender, amount);
        emit FeesWithdrawn(msg.sender, token, amount);
    }

    /* ========== VIEW FUNCTIONS ========== */

    function getBorrowerStats(address borrower, address token) 
        external 
        view 
        returns (uint256 vaultBalance, uint256 totalPaidToPool) 
    {
        vaultBalance = vault[borrower][token];
        totalPaidToPool = 0;

        bytes32[] memory refs = borrowerLoans[borrower];
        for (uint256 i = 0; i < refs.length; i++) {
            Loan storage loan = loans[refs[i]];
            if (loan.token == token) {
                totalPaidToPool += loan.totalPaid;
            }
        }
    }

    function getLenderStats(address lender, address token) 
        external 
        view 
        returns (
            uint256 deposit,
            uint256 poolShare,
            uint256 totalFeesEarned,
            uint256 feesClaimed
        ) 
    {
        deposit = vault[lender][token];
        feesClaimed = feeDebt[lender][token];

        uint256 contribution = lenderContribution[lender][token];
        uint256 totalAccumulatedFee = (contribution * cumulativeFeePerToken[token]) / FEE_PRECISION;
        totalFeesEarned = totalAccumulatedFee;
        poolShare = deposit + (totalFeesEarned - feesClaimed);
    }

    function getProtocolStats(address token) 
        external 
        view 
        returns (
            uint256 numLenders,
            uint256 numBorrowers,
            uint256 totalLenderDeposits,
            uint256 totalBorrowed,
            uint256 totalOutstanding,
            uint256 totalPaid
        ) 
    {
        numLenders = lenders.length;
        totalLenderDeposits = 0;
        for (uint256 i = 0; i < lenders.length; i++) {
            totalLenderDeposits += vault[lenders[i]][token];
        }

        numBorrowers = borrowers.length;
        totalBorrowed = 0;
        totalOutstanding = 0;
        totalPaid = 0;
        for (uint256 i = 0; i < borrowers.length; i++) {
            bytes32[] memory ids = borrowerLoans[borrowers[i]];
            for (uint256 j = 0; j < ids.length; j++) {
                Loan storage loan = loans[ids[j]];
                if (loan.token == token) {
                    totalBorrowed += loan.principal;
                    totalOutstanding += loan.outstanding;
                    totalPaid += loan.totalPaid;
                }
            }
        }
    }

    function getAllBorrowers() external view returns (address[] memory) {
        return borrowers;
    }

    function getAllLenders() external view returns (address[] memory) {
        return lenders;
    }

    function getLoans(address borrower) external view returns (Loan[] memory) {
        bytes32[] memory ids = borrowerLoans[borrower];
        Loan[] memory result = new Loan[](ids.length);
        for (uint256 i = 0; i < ids.length; i++) {
            result[i] = loans[ids[i]];
        }
        return result;
    }
}