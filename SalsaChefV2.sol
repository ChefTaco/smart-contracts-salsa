/*

                   oooo                     
                   `888                     
 .oooo.o  .oooo.    888   .oooo.o  .oooo.   
d88(  "8 `P  )88b   888  d88(  "8 `P  )88b  
`"Y88b.   .oP"888   888  `"Y88b.   .oP"888  CHEF
o.  )88b d8(  888   888  o.  )88b d8(  888  
8""888P' `Y888""8o o888o 8""888P' `Y888""8o

Website     https://salsa.tacoparty.finance

    Note: We used the Sandman Delirium MasterChef as the original Paladin-audited base, as it is MIT licensed.  
    The MC also has an added section for Variable Emissions, including leng-of-staking features.

*/

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "contracts/SalsaToken.sol";

// Salsa Dev:  We start with standard Sandman Delirium MC fork, with added mint to the burn address, and hooks
//   for variable emissions (updates mass if needed and calls an emissions rate function)
//   Variable emissions and emission change policies will be documented in online references.

// MasterChef is the master of Salsa. He can make Salsa and he is a fair guy.
//
// Note that it's ownable and the owner wields tremendous power. The ownership
// will be transferred to a governance smart contract once SALSA is sufficiently
// distributed and the community can show to govern itself.
//
// Have fun reading it. Hopefully it's bug-free. God bless.
contract MasterChefV2 is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // Info of each user.
    struct UserInfo {
        uint256 amount;         // How many LP tokens the user has provided.
        uint256 rewardDebt;     // Reward debt. See explanation below.
        uint256 lastWithdraw;   // Added last block the user withdrew.
        //
        // We do some fancy math here. Basically, any point in time, the amount of SALSAs
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accSalsaPerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
        //   1. The pool's `accSalsaPerShare` (and `lastRewardBlock`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }

    // Info of each pool.
    struct PoolInfo {
        IERC20 lpToken;           // Address of LP token contract.
        uint256 allocPoint;       // How many allocation points assigned to this pool. SALSAs to distribute per block.
        uint256 lastRewardBlock;  // Last block number that SALSAs distribution occurs.
        uint256 accSalsaPerShare;   // Accumulated SALSAs per share, times 1e12. See below.
        uint16 depositFeeBP;      // Deposit fee in basis points
        uint256 lpSupply;
        bool offersRetentionRewards; // apply a length of staking reward to the pool
        }

    uint256 public salsaMaximumSupply = 150 * (10 ** 3) * (10 ** 18); // 150,000 salsa

    // The SALSA TOKEN!
    SalsaParty public immutable salsa;
    // SALSA tokens created per block.
    uint256 public salsaPerBlock;
    // Deposit Fee address
    address public feeAddress;

    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;
    // The block number when SALSA mining starts.
    uint256 public startBlock;
    // The block number when SALSA mining ends.
    uint256 public emmissionEndBlock = type(uint256).max;
    // Maximum emission rate.
    // 1000000000000000000 is 1/block
    uint256 public constant MAX_EMISSION_RATE = 200000000000000000;  // 0.2/block
    IERC20 public usdc;
    // 30% bonus rewards for longer staking
    uint256 public constant STAKING_LENGTH_MULT = 30; 
    uint256 public constant STAKING_LENGTH_BLOCKS = 108000;  // roughly 3 days at 2.4s/block

    event addPool(uint256 indexed pid, address lpToken, uint256 allocPoint, uint256 depositFeeBP);
    event setPool(uint256 indexed pid, address lpToken, uint256 allocPoint, uint256 depositFeeBP);
    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event SetEmissionRate(address indexed caller, uint256 previousAmount, uint256 newAmount);
    event SetFeeAddress(address indexed user, address indexed newAddress);
    event SetStartBlock(uint256 newStartBlock);
    event SetStartPoolRewardBlock(uint256 pid);
    
    constructor(
        SalsaParty _salsa,
        address _feeAddress,
        uint256 _salsaPerBlock,
        uint256 _startBlock,
        address _usdcAddress
    ) {
        require(_feeAddress != address(0), "fee!nonzero");

        salsa = _salsa;
        feeAddress = _feeAddress;
        salsaPerBlock = _salsaPerBlock;
        startBlock = _startBlock;
        
        require(_usdcAddress != address(0), "usdc!nonzero");
        usdc = IERC20(_usdcAddress);
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    mapping(IERC20 => bool) public poolExistence;
    modifier nonDuplicated(IERC20 _lpToken) {
        require(poolExistence[_lpToken] == false, "nonDuplicated: duplicated");
        _;
    }

    // Add a new lp to the pool. Can only be called by the owner.
    function add(uint256 _allocPoint, IERC20 _lpToken, uint16 _depositFeeBP, bool _offersRetentionRewards, bool _withUpdate) external onlyOwner nonDuplicated(_lpToken) {
        // Make sure the provided token is ERC20
        _lpToken.balanceOf(address(this));

        require(_depositFeeBP <= 400, "add: inv dep fee basis points");
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        totalAllocPoint = totalAllocPoint + _allocPoint;
        poolExistence[_lpToken] = true;

        poolInfo.push(PoolInfo({
        lpToken : _lpToken,
        allocPoint : _allocPoint,
        lastRewardBlock : lastRewardBlock,
        accSalsaPerShare : 0,
        depositFeeBP : _depositFeeBP,
        lpSupply: 0,
        offersRetentionRewards : _offersRetentionRewards
        }));

        emit addPool(poolInfo.length - 1, address(_lpToken), _allocPoint, _depositFeeBP);
    }

    // Update the given pool's SALSA allocation point and deposit fee. Can only be called by the owner.
    function set(uint256 _pid, uint256 _allocPoint, uint16 _depositFeeBP, bool _withUpdate) external onlyOwner {
        require(_depositFeeBP <= 401, "set: inv dep fee basis points");
        if (_withUpdate) {
            massUpdatePools();
        }
        totalAllocPoint = totalAllocPoint - poolInfo[_pid].allocPoint + _allocPoint;
        poolInfo[_pid].allocPoint = _allocPoint;
        poolInfo[_pid].depositFeeBP = _depositFeeBP;

        emit setPool(_pid, address(poolInfo[_pid].lpToken), _allocPoint, _depositFeeBP);
    }

    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint256 _from, uint256 _to) public view returns (uint256) {
        // As we set the multiplier to 0 here after emmissionEndBlock
        // deposits aren't blocked after farming ends.
        if (_from > emmissionEndBlock)
            return 0;
        if (_to > emmissionEndBlock)
            return emmissionEndBlock - _from;
        else
            return _to - _from;
    }

    // View function to see pending SALSAs on frontend.
    function pendingSalsa(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accSalsaPerShare = pool.accSalsaPerShare;
        if (block.number > pool.lastRewardBlock && pool.lpSupply != 0 && totalAllocPoint > 0) {
            uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
            uint256 salsaReward = (multiplier * salsaPerBlock * pool.allocPoint) / totalAllocPoint;
            accSalsaPerShare = accSalsaPerShare + ((salsaReward * 1e12) / pool.lpSupply);
        }

        return ((user.amount * accSalsaPerShare) /  1e12) - user.rewardDebt;
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }

        if (pool.lpSupply == 0 || pool.allocPoint == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }

        uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
        uint256 salsaReward = (multiplier * salsaPerBlock * pool.allocPoint) / totalAllocPoint;

        // This shouldn't happen, but just in case we stop rewards.
        if (salsa.totalSupply() > salsaMaximumSupply)
            salsaReward = 0;
        else if ((salsa.totalSupply() + salsaReward) > salsaMaximumSupply)
            salsaReward = salsaMaximumSupply - salsa.totalSupply();

        if (salsaReward > 0)
        {
            if((salsaReward / 10) > 0)
                salsa.mint(feeAddress, salsaReward / 10);

            salsa.mint(address(this), salsaReward);
        }

        // The first time we reach Salsa max supply we solidify the end of farming.
        if (salsa.totalSupply() >= salsaMaximumSupply && emmissionEndBlock == type(uint256).max)
            emmissionEndBlock = block.number;

        pool.accSalsaPerShare += ((salsaReward * 1e12) / pool.lpSupply);
        pool.lastRewardBlock = block.number;
    }

    // Send rewards to staker
    function sendRewards(PoolInfo storage pool, UserInfo storage user, uint256 _pid) internal {
        if (user.amount > 0) {
            uint256 pending = ((user.amount * pool.accSalsaPerShare) / 1e12) - user.rewardDebt;
            if (pending > 0) {
                safeSalsaTransfer(msg.sender, pending);
                handleStakingRewards(_pid, pending);
            }
        }
    }

    // Deposit LP tokens to MasterChef for SALSA allocation.
    //      Note: Web UI 'Harvest' just uses the Deposit function with 0 amount
    function deposit(uint256 _pid, uint256 _amount) external nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);
        sendRewards(pool, user, _pid);
        if (_amount > 0) {
            uint256 balanceBefore = pool.lpToken.balanceOf(address(this));
            pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
            _amount = pool.lpToken.balanceOf(address(this)) - balanceBefore; // Catches transfer fee token deposits
            require(_amount > 0, "no deposits of 0 size");

            if (pool.depositFeeBP > 0) {
                uint256 depositFee = (_amount * pool.depositFeeBP) / 10000;
                pool.lpToken.safeTransfer(feeAddress, depositFee);
                user.amount = user.amount + _amount - depositFee;
                pool.lpSupply = pool.lpSupply + _amount - depositFee;
            } else {
                user.amount = user.amount + _amount;
                pool.lpSupply = pool.lpSupply + _amount;
            }
        }
        user.rewardDebt = (user.amount * pool.accSalsaPerShare) / 1e12;

        // Add a mass update for emissions, if needed
        updateEmissionIfNeeded();

        emit Deposit(msg.sender, _pid, _amount);
    }

    // Withdraw LP tokens from MasterChef.
    function withdraw(uint256 _pid, uint256 _amount) external nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        updatePool(_pid);
        sendRewards(pool, user, _pid);
        if (_amount > 0) {
            user.amount = user.amount - _amount;
            pool.lpToken.safeTransfer(address(msg.sender), _amount);
            pool.lpSupply = pool.lpSupply - _amount;
            user.lastWithdraw = block.number;
        }
        user.rewardDebt = (user.amount * pool.accSalsaPerShare) / 1e12;

        // Add a mass update for emissions, if needed
        updateEmissionIfNeeded();

        emit Withdraw(msg.sender, _pid, _amount);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) external nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        uint256 amount = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;
        pool.lpToken.safeTransfer(address(msg.sender), amount);

        // In the case of an accounting error, we choose to let the user emergency withdraw anyway
        if (pool.lpSupply >=  amount)
            pool.lpSupply = pool.lpSupply - amount;
        else
            pool.lpSupply = 0;

        emit EmergencyWithdraw(msg.sender, _pid, amount);
    }

    // Safe salsa transfer function, just in case if rounding error causes pool to not have enough SALSAs.
    function safeSalsaTransfer(address _to, uint256 _amount) internal {
        uint256 salsaBal = salsa.balanceOf(address(this));
        bool transferSuccess = false;
        if (_amount > salsaBal) {
            transferSuccess = salsa.transfer(_to, salsaBal);
        } else {
            transferSuccess = salsa.transfer(_to, _amount);
        }
        require(transferSuccess, "safeSalsaTransfer: transfer failed");
    }

    function setFeeAddress(address _feeAddress) external onlyOwner {
        require(_feeAddress != address(0), "!nonzero");
        feeAddress = _feeAddress;
        emit SetFeeAddress(msg.sender, _feeAddress);
    }

    function setStartBlock(uint256 _newStartBlock) external onlyOwner {
        require(block.number < startBlock, "cannot change start block if sale has already commenced");
        require(block.number < _newStartBlock, "cannot set start block in the past");
        startBlock = _newStartBlock;

        emit SetStartBlock(startBlock);
    }

    // this should be updated every 5 mins or so via Variable Emissions, so likely never called
    function setEmissionRate(uint256 _salsaPerBlock) public onlyOwner {
        require(_salsaPerBlock > 0);
        require(_salsaPerBlock <= MAX_EMISSION_RATE, 'Above max emissions.'); // added for safety

        massUpdatePools();
        salsaPerBlock = _salsaPerBlock;
        
        emit SetEmissionRate(msg.sender, salsaPerBlock, _salsaPerBlock);
    }

    //
    // Salsa Dev: Added Variable emissions code
    //  We keep it simple and opt for a linear, rather than floating point logarithmic function
    //
    //
    uint public topPrice = 100; // 100$ upped initial top
    uint public bottomPrice = 1; // 1$
    uint public lastBlockUpdate = 0;
    uint public emissionUpdateInterval = 100; // now approx 5 mins at 2 blocks/seconds (Paladin high severity finding fix) 
    address public usdcSalsaLP = address(0x0); // set after listing.

    event UpdateEmissionRate(address indexed user, uint256 goosePerBlock);

    // For checking prices to link emission rate
    function setUSDCSalsaLPAddress(address _address) public onlyOwner {
        require (_address!=address(0));  // added for good measure
        usdcSalsaLP = _address;
    }    

    function updateEmissionIfNeeded() public {

        if (usdcSalsaLP==address(0x0)){
            return; 
        }
    
        uint priceCents = bottomPrice * 100;
        if (block.number - lastBlockUpdate > emissionUpdateInterval) {
            lastBlockUpdate = block.number;
        
            uint salsaBalance = salsa.balanceOf(usdcSalsaLP);
          
            if (salsaBalance > 0) {
                // usdc token decimals = 6, token decimals = 18 ,(18-x)=12 + 2  = 14 to convert to cents
                priceCents = usdc.balanceOf(usdcSalsaLP) * 1e14 / salsaBalance;
            }

            // Update pools before changing the emission rate
            massUpdatePools();
            uint256 emissionRatePercent = getEmissionRatePercent(priceCents);
            salsaPerBlock = MAX_EMISSION_RATE / 100 * emissionRatePercent;
        }
    }

    function getSalsaPriceCents() public view returns (uint256 spc){
         uint salsaBalance = salsa.balanceOf(usdcSalsaLP);
          if (salsaBalance > 0) {
            uint256 priceCents = usdc.balanceOf(usdcSalsaLP) * 1e14 / salsaBalance;
            return priceCents;
          }
          return 0;
    }

    function getEmissionRatePercent(uint256 salsaPriceCents) public view returns (uint256 epr) {
        
        if (salsaPriceCents>=topPrice*100){return (1);}
        if (salsaPriceCents<=bottomPrice*100){return (100);}

        uint256 salsaPricePercentOfTop = (salsaPriceCents * 100) / (topPrice * 100);

        uint256 salsaEmissionPercent = 100 - salsaPricePercentOfTop;
        if (salsaEmissionPercent <= 0)
            salsaEmissionPercent = 1;

        return salsaEmissionPercent;
    }

    function updateEmissionParameters(uint _topPrice, uint _bottomPrice, uint _emissionUpdateInterval) public onlyOwner {
        topPrice = _topPrice;
        bottomPrice = _bottomPrice;
        emissionUpdateInterval = _emissionUpdateInterval;
    }

    //Update emission rate
    function updateEmissionRate(uint256 _salsaPerBlock) public onlyOwner {
        require(_salsaPerBlock <= MAX_EMISSION_RATE, 'Too high'); // fix for Paladin low finding
        massUpdatePools();
        salsaPerBlock = _salsaPerBlock;
        emit UpdateEmissionRate(msg.sender, _salsaPerBlock);
    }

    //
    //  Length of staking bonus rewards
    //

    // Determine if a pool should qualify for retention rewards
    function isStakingRewardsEligible(uint256 _pid) public view returns (bool isEligible) {
        return(poolInfo[_pid].offersRetentionRewards);
    }

    //  Added length-of-staking loyalty code
    function getStakingRewardsMultiplier(uint256 _pid) public view returns (uint256 multiplier){
                UserInfo storage user = userInfo[_pid][msg.sender];
                uint256 lastWithdraw = user.lastWithdraw;
                uint256 blockDifference;
                if(user.amount > 0) {
                    if(isStakingRewardsEligible(_pid)) {
                        if(lastWithdraw > block.number) lastWithdraw = block.number;
                        blockDifference = block.number - lastWithdraw;
                        if(blockDifference >= STAKING_LENGTH_BLOCKS)
                            return(STAKING_LENGTH_MULT);
                        else
                            return(
                                (((blockDifference * 100) /
                                STAKING_LENGTH_BLOCKS)
                                * 
                                STAKING_LENGTH_MULT)
                                / 100
                            );
                    }
                }
                return 0;
    }

    // handle any bonus rewards to be sent to the staker
    function handleStakingRewards(uint256 _pid, uint256 amount) internal {
        uint256 mint_amt = (getStakingRewardsMultiplier(_pid) * amount) / 100;
        require(mint_amt <= (amount/2), 'reward bonus too big');  // sanity check
        if(mint_amt > 0)
            salsa.mint(msg.sender, mint_amt);
    }
}