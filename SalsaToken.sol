// SPDX-License-Identifier: MIT

/*
                   oooo                     
                   `888                     
 .oooo.o  .oooo.    888   .oooo.o  .oooo.   
d88(  "8 `P  )88b   888  d88(  "8 `P  )88b  
`"Y88b.   .oP"888   888  `"Y88b.   .oP"888  TOKEN
o.  )88b d8(  888   888  o.  )88b d8(  888  
8""888P' `Y888""8o o888o 8""888P' `Y888""8o

Website     https://salsa.tacoparty.finance
*/

pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/draft-ERC20Permit.sol";

import "./libs/IUniRouter02.sol";
import "./libs/IUniswapV2Pair.sol";
import "./libs/IUniswapV2Factory.sol";

contract SalsaParty is ERC20, Ownable, ERC20Permit {

    // Transfer tax rate in basis points. (5.0%)
    uint16 public transferTaxRate = 500;
    // Max transfer amount rate in basis points. (default is 5% of total supply)
    uint16 public constant maxTransferAmountRate = 500;
    // Default # of tokens to mint
    uint256 public constant MINT_AMOUNT = 50000 ether;

    address public constant BURN_ADDRESS = 0x000000000000000000000000000000000000dEaD;

    // Where to ship liquidity
    address public feeAddress;

    // Automatic swap and liquify enabled
    bool public swapAndLiquifyEnabled = true;
    // Min amount to liquify. (default 200 SALSAs)
    uint256 public minAmountToLiquify = 200 ether;
    // Max amount for minAmountToLiquify
    uint256 public constant MIN_AMOUNT_LIQUIFY_MAX = 200 ether;
    // The swap router, modifiable.
    IUniRouter02 public salsaSwapRouter;
    // The trading pair
    address public salsaSwapPair;
    // In swap and liquify
    bool private _inSwapAndLiquify;
    // Total amount we've liquified
    uint256 public totalLiquified = 0;

    // The operator can only update the transfer tax rate
    address private _operator;

    // mapping of addresses that should be excluded from swap fees
    mapping (address => bool) private _isExcludedFromFee;

        // Events
    event OperatorTransferred(address indexed previousOperator, address indexed newOperator);
    event SwapAndLiquifyEnabledUpdated(address indexed operator, bool enabled);
    event MinAmountToLiquifyUpdated(address indexed operator, uint256 previousAmount, uint256 newAmount);
    event SalsaSwapRouterUpdated(address indexed operator, address indexed router, address indexed pair);
    event SwapAndLiquify(uint256 tokensSwapped, uint256 ethReceived, uint256 tokensIntoLiqudity);

    modifier onlyOperator() {
        require(_operator == msg.sender, "caller is not the operator");
        _;
    }
    
    modifier lockTheSwap {
        _inSwapAndLiquify = true;
        _;
        _inSwapAndLiquify = false;
    }

    modifier transferTaxFree {
        uint16 _transferTaxRate = transferTaxRate;
        transferTaxRate = 0;
        _;
        transferTaxRate = _transferTaxRate;
    }

    constructor(address feeaddr) ERC20("SalsaParty", "SALSA") ERC20Permit("SalsaParty") {
        _operator = _msgSender();
        emit OperatorTransferred(address(0), _operator);

        require(feeaddr != address(0x0), 'usdc is zero');
        feeAddress = feeaddr;

        _mint(address(msg.sender), MINT_AMOUNT);

        // setup the initial transfer fee exclusion list
        _isExcludedFromFee[msg.sender] = true;
        _isExcludedFromFee[address(this)] = true;
        _isExcludedFromFee[BURN_ADDRESS] = true;
        _isExcludedFromFee[feeAddress] = true;
    }

    /// @dev To receive ETH from SwapRouter when swapping
    receive() external payable {}

    function mint(address _to, uint256 _amount) public onlyOwner {
        _mint(_to, _amount);
    }

    function getOwner() external view returns (address) {
        return owner();
    }

    function excludeFromFee(address account) public onlyOperator {
        _isExcludedFromFee[account] = true;
    }
    
    function includeInFee(address account) public onlyOperator {
        _isExcludedFromFee[account] = false;
    }

    /// @dev  Determine if transfer tax should be taken
    function isTaxExcluded(address sender, address recipient) internal view returns(bool) {
        address _owner = owner();
        if(
            _isExcludedFromFee[sender] || _isExcludedFromFee[recipient]
            || (sender == salsaSwapPair)
            || (transferTaxRate == 0)
            || (sender == address(salsaSwapRouter))
            || (sender == _owner || recipient == _owner)
        )
            return true;

        return false;
    }

    /// @dev Transfer override to take a transfer tax
    function _transfer(address sender, address recipient, uint256 amount) internal virtual override {
        if(amount > 0)
        {
            if(isTaxExcluded(sender, recipient) || _inSwapAndLiquify)
            {
                super._transfer(sender, recipient, amount);
            }
            else
            {
                // swap and liquify
                if (
                    address(salsaSwapRouter) != address(0)
                    && salsaSwapPair != address(0)
                    && swapAndLiquifyEnabled == true
                ) {
                    // Converts contract contents into liquidity
                    swapAndLiquify();
                }

                // default tax is 5.0% of every transfer
                uint256 taxAmount = amount * transferTaxRate / 10000;

                // default 95% of transfer sent to recipient
                uint256 sendAmount = amount - taxAmount;
                require(amount == sendAmount + taxAmount, "tax value invalid");

                super._transfer(sender, address(this), taxAmount);
                super._transfer(sender, recipient, sendAmount);
            }
        }
    }

    /**
    * @dev Returns the max transfer amount.
    */
    function maxTransferAmount() public view returns (uint256) {
        return ((totalSupply() * maxTransferAmountRate) / 10000);
    }

    /// @dev update the minimum amount to liquify contained within the contract
    function setMinAmountToLiquify(uint256 amount) public onlyOperator {
        require(amount <= MIN_AMOUNT_LIQUIFY_MAX, 'liq min too high');
        uint256 previousMin = minAmountToLiquify;
        minAmountToLiquify = amount;
        emit MinAmountToLiquifyUpdated(_operator, previousMin, amount);
    }

    /// @dev Swap and liquify
    function swapAndLiquify() private lockTheSwap transferTaxFree {
        uint256 contractTokenBalance = balanceOf(address(this));
        uint256 _maxTransferAmount = maxTransferAmount();
        contractTokenBalance = contractTokenBalance > _maxTransferAmount ? _maxTransferAmount : contractTokenBalance;

        if (contractTokenBalance >= minAmountToLiquify) {
            // only min amount to liquify
            uint256 liquifyAmount = minAmountToLiquify;

            // split the liquify amount into halves
            uint256 half = liquifyAmount / 2;
            uint256 otherHalf = liquifyAmount - half;

            // capture the contract's current ETH balance.
            // this is so that we can capture exactly the amount of ETH that the
            // swap creates, and not make the liquidity event include any ETH that
            // has been manually sent to the contract
            uint256 initialBalance = address(this).balance;

            // swap tokens for ETH
            swapTokensForEth(half);

            // how much ETH did we just swap into?
            uint256 newBalance = address(this).balance - initialBalance;

            // add liquidity
            addLiquidity(otherHalf, newBalance);

            totalLiquified += liquifyAmount;

            emit SwapAndLiquify(half, newBalance, otherHalf);
        }
    }

    /// @dev Swap tokens for eth
    function swapTokensForEth(uint256 tokenAmount) private {
        // generate the salsaSwap pair path of token -> weth
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = salsaSwapRouter.WETH();

        _approve(address(this), address(salsaSwapRouter), tokenAmount);

        // make the swap
        salsaSwapRouter.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0, // accept any amount of ETH
            path,
            address(this),
            block.timestamp
        );
    }

    /// @dev Add liquidity
    function addLiquidity(uint256 tokenAmount, uint256 ethAmount) private {
        // approve token transfer to cover all possible scenarios
        _approve(address(this), address(salsaSwapRouter), tokenAmount);

        // add the liquidity
        salsaSwapRouter.addLiquidityETH{value: ethAmount}(
            address(this),
            tokenAmount,
            0, // slippage is unavoidable
            0, // slippage is unavoidable
            operator(),
            block.timestamp
        );
    }
    
    /**
     * @dev Update the swapAndLiquifyEnabled.
     * Can only be called by the current operator.
     */
    function updateSwapAndLiquifyEnabled(bool _enabled) public onlyOperator {
        emit SwapAndLiquifyEnabledUpdated(msg.sender, _enabled);
        swapAndLiquifyEnabled = _enabled;
    }

    /**
     * @dev Update the swap router.
     * Can only be called by the current operator.
     */
    function updateSalsaSwapRouter(address _router) public onlyOperator {
        require(_router != address(0), "invalid router");
        salsaSwapRouter = IUniRouter02(_router);
        salsaSwapPair = IUniswapV2Factory(salsaSwapRouter.factory()).getPair(address(this), salsaSwapRouter.WETH());
        require(salsaSwapPair != address(0), "invalid pair address");
        emit SalsaSwapRouterUpdated(msg.sender, address(salsaSwapRouter), salsaSwapPair);
    }

    /**
     * @dev Returns the address of the current operator.
     */
    function operator() public view returns (address) {
        return _operator;
    }

    /**
     * @dev Transfers operator of the contract to a new account (`newOperator`).
     * Can only be called by the current operator.
     */
    function transferOperator(address newOperator) public onlyOperator {
        require(newOperator != address(0), "new operator == 0");
        emit OperatorTransferred(_operator, newOperator);
        _operator = newOperator;
    }
}