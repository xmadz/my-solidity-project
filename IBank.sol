// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// IBank 接口
interface IBank {
    // 事件
    event Deposited(address indexed user, uint256 amount);
    event Withdrawn(address indexed admin, uint256 amount);
    event AdminTransferred(address indexed previousAdmin, address indexed newAdmin);
    
    // 函数声明
    function admin() external view returns (address);
    function deposits(address) external view returns (uint256);
    function topDepositors(uint256) external view returns (address);
    function withdraw(uint256 _amount) external;
    function getContractBalance() external view returns (uint256);
    function getTopDepositorsDetails() external view returns (address[3] memory, uint256[3] memory);
    function getUserRank(address _user) external view returns (uint256);
    function getMinDeposit() external view returns (uint256);
}

// Bank 合约，实现 IBank 接口
contract Bank is IBank {
    address public override admin;
    mapping(address => uint256) public override deposits;
    address[3] public override topDepositors;
    
    // 事件已经在接口中声明，这里不需要重新声明
    // 只需要在合约中触发这些事件
    
    modifier onlyAdmin() {
        require(msg.sender == admin, "Only admin can call this function");
        _;
    }
    
    constructor() payable {
        admin = msg.sender;
    }
    
    receive() external payable virtual {
        _deposit(msg.sender, msg.value);
    }
    
    fallback() external payable virtual {
        _deposit(msg.sender, msg.value);
    }
    function transferETH(address payable _to, uint256 amount) external payable{
    _to.transfer(amount);
}
    function _deposit(address _user, uint256 _amount) internal virtual {
        require(_amount > 0, "Deposit amount must be greater than 0");
        
        deposits[_user] += _amount;
        _updateTopDepositors(_user);
        
        emit Deposited(_user, _amount);
    }
    
    function _updateTopDepositors(address _user) internal {
        uint256 userDeposit = deposits[_user];
        
        // 检查用户是否已经在top3中
        for (uint i = 0; i < 3; i++) {
            if (topDepositors[i] == _user) {
                // 用户已在数组中，需要重新排序
                _sortTopDepositors();
                return;
            }
        }
        
        // 用户不在数组中，检查是否能进入前3
        for (uint i = 0; i < 3; i++) {
            if (topDepositors[i] == address(0)) {
                // 有空位，直接添加
                topDepositors[i] = _user;
                _sortTopDepositors();
                return;
            }
            
            if (userDeposit > deposits[topDepositors[i]]) {
                // 找到插入位置，将后面的元素后移
                for (uint j = 2; j > i; j--) {
                    topDepositors[j] = topDepositors[j - 1];
                }
                topDepositors[i] = _user;
                return;
            }
        }
    }
    
    function _sortTopDepositors() internal {
        // 简单的冒泡排序
        for (uint i = 0; i < 2; i++) {
            for (uint j = 0; j < 2 - i; j++) {
                if (deposits[topDepositors[j]] < deposits[topDepositors[j + 1]]) {
                    // 交换位置
                    address temp = topDepositors[j];
                    topDepositors[j] = topDepositors[j + 1];
                    topDepositors[j + 1] = temp;
                }
            }
        }
    }
    
    function withdraw(uint256 _amount) external virtual override onlyAdmin {
        require(_amount > 0, "Withdrawal amount must be greater than 0");
        require(_amount <= address(this).balance, "Insufficient contract balance");
        
        payable(admin).transfer(_amount);
        
        emit Withdrawn(admin, _amount);
    }
    
    function getContractBalance() external view override returns (uint256) {
        return address(this).balance;
    }
    
    function getTopDepositorsDetails() external view override returns (address[3] memory, uint256[3] memory) {
        uint256[3] memory amounts;
        for (uint i = 0; i < 3; i++) {
            if (topDepositors[i] != address(0)) {
                amounts[i] = deposits[topDepositors[i]];
            }
        }
        return (topDepositors, amounts);
    }
    
    function getUserRank(address _user) external view override returns (uint256) {
        for (uint i = 0; i < 3; i++) {
            if (topDepositors[i] == _user) {
                return i + 1; // 返回1-3的排名
            }
        }
        return 0; // 不在前3名
    }
    
    // 为接口提供默认实现（返回0，表示无最小存款限制）
    function getMinDeposit() external pure virtual override returns (uint256) {
        return 0;
    }
}

// BigBank 合约，继承自 Bank
contract BigBank is Bank {
    // 最小存款金额
    uint256 public constant MIN_DEPOSIT = 1 wei;
    
    // 修饰器：检查存款金额是否满足最低要求
    modifier minimumDeposit() {
        require(msg.value >= MIN_DEPOSIT, "Deposit must be at least 1 Wei");
        _;
    }
    
    // 重写 receive 函数，添加金额检查
    receive() external payable override minimumDeposit {
        _deposit(msg.sender, msg.value);
    }
    
    // 重写 fallback 函数，添加金额检查
    fallback() external payable override minimumDeposit {
        _deposit(msg.sender, msg.value);
    }
    
    // 重写 _deposit 函数，确保满足最低存款要求
    function _deposit(address _user, uint256 _amount) internal override {
        require(_amount >= MIN_DEPOSIT, "Deposit must be at least 1 Wei");
        super._deposit(_user, _amount);
    }
    
    // 转移管理员权限
    function transferAdmin(address _newAdmin) external onlyAdmin {
        require(_newAdmin != address(0), "New admin cannot be the zero address");
        require(_newAdmin != admin, "New admin cannot be the same as current admin");
        
        address previousAdmin = admin;
        admin = _newAdmin;
        
        emit AdminTransferred(previousAdmin, _newAdmin);
    }
    
    // 重写 getMinDeposit 函数，返回实际的最小存款金额
    function getMinDeposit() external pure  override returns (uint256) {
        return MIN_DEPOSIT;
    }
}

contract Admin {
    // 合约所有者
    address public owner;
    
    // 事件
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event FundsWithdrawn(address indexed bank, uint256 amount);
    event FundsReceived(address indexed from, uint256 amount);
    
    // 修饰器：仅所有者可调用
    modifier onlyOwner() {
        require(msg.sender == owner, "Admin: caller is not the owner");
        _;
    }
    
    // 构造函数：设置合约所有者
    constructor() {
        owner = msg.sender;
    }
    
    // 接收以太币的函数
    receive() external payable {
        emit FundsReceived(msg.sender, msg.value);
    }
    
    // 回退函数
    fallback() external payable {
        emit FundsReceived(msg.sender, msg.value);
    }
    
    // 内部取款函数，避免递归调用问题
    function _adminWithdrawInternal(IBank bank, uint256 amount) internal {
        // 检查 Bank 合约余额是否足够
        uint256 bankBalance = bank.getContractBalance();
        require(bankBalance >= amount, "Admin: insufficient balance in bank contract");
        
        // 检查当前 Admin 合约是否是 Bank 合约的管理员
        address bankAdmin = bank.admin();
        require(bankAdmin == address(this), "Admin: this contract is not the admin of the target bank");
        
        // 记录取款前的余额
        uint256 initialBalance = address(this).balance;
        
        // 调用 Bank 合约的 withdraw 方法
        bank.withdraw(amount);
        
        // 验证资金是否成功转移到当前合约
        uint256 finalBalance = address(this).balance;
        uint256 actualReceived = finalBalance - initialBalance;
        
        require(actualReceived >= amount, "Admin: withdrawal amount mismatch");
        
        emit FundsWithdrawn(address(bank), actualReceived);
    }
    
    // 管理员取款函数：从指定的 Bank 合约提取资金到当前 Admin 合约
    function adminWithdraw(IBank bank, uint256 amount) external onlyOwner {
        _adminWithdrawInternal(bank, amount);
    }
    
    // 批量从多个 Bank 合约取款
    function batchAdminWithdraw(IBank[] calldata banks, uint256[] calldata amounts) external onlyOwner {
        require(banks.length == amounts.length, "Admin: arrays length mismatch");
        
        for (uint256 i = 0; i < banks.length; i++) {
            if (banks[i].admin() == address(this)) {
                uint256 bankBalance = banks[i].getContractBalance();
                uint256 withdrawAmount = amounts[i] <= bankBalance ? amounts[i] : bankBalance;
                
                if (withdrawAmount > 0) {
                    _adminWithdrawInternal(banks[i], withdrawAmount);
                }
            }
        }
    }
    
    // 从当前 Admin 合约提取资金到所有者地址
    function withdrawToOwner(uint256 amount) external onlyOwner {
        require(amount <= address(this).balance, "Admin: insufficient balance");
        
        payable(owner).transfer(amount);
    }
    
    // 转移合约所有权
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Admin: new owner is the zero address");
        require(newOwner != owner, "Admin: new owner is the same as current owner");
        
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }
    
    // 获取当前合约余额
    function getAdminBalance() external view returns (uint256) {
        return address(this).balance;
    }
    
    // 检查是否是特定 Bank 合约的管理员
    function isBankAdmin(IBank bank) external view returns (bool) {
        return bank.admin() == address(this);
    }
    
    // 获取可提取的 Bank 合约余额（仅当当前合约是管理员时）
    function getWithdrawableBalance(IBank bank) external view returns (uint256) {
        if (bank.admin() == address(this)) {
            return bank.getContractBalance();
        }
        return 0;
    }
    
    // 紧急情况下提取所有资金到所有者
    function emergencyWithdrawAll() external onlyOwner {
        uint256 balance = address(this).balance;
        if (balance > 0) {
            payable(owner).transfer(balance);
        }
    }
}
contract SendETH {
    // 构造函数，payable使得部署的时候可以转eth进去
    constructor() payable{}
    // receive方法，接收eth时被触发
    receive() external payable{}
    // 用transfer()发送ETH  0xa6165bbb69f7e8f3d960220B5F28e990ea5F630D
function transferETH(address payable _to, uint256 amount) external payable{
    _to.transfer(amount);
}


error CallFailed(); // 用call发送ETH失败error
// call()发送ETH
function callETH(address payable _to, uint256 amount) external payable{
    // 处理下call的返回值，如果失败，revert交易并发送error
    (bool success,) = _to.call{value: amount}("");
    if(!success){
        revert CallFailed();
    }
}

}
