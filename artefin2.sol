// SPDX-License-Identifier: GPL

pragma solidity ^0.8.0;

library Address {
    /**
     * @dev Returns true if `account` is a contract.
     *
     * This test is non-exhaustive, and there may be false-negatives: during the
     * execution of a contract's constructor, its address will be reported as
     * not containing a contract.
     *
     * > It is unsafe to assume that an address for which this function returns
     * false is an externally-owned account (EOA) and not a contract.
     */
    function isContract(address account) internal view returns (bool) {
        // This method relies in extcodesize, which returns 0 for contracts in
        // construction, since the code is only stored at the end of the
        // constructor execution.

        uint256 size;
        // solhint-disable-next-line no-inline-assembly
        assembly { size := extcodesize(account) }
        return size > 0;
    }
}

abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        return msg.data;
    }
}

abstract contract Ownable is Context {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /**
     * @dev Initializes the contract setting the deployer as the initial owner.
     */
    constructor() {
        _transferOwnership(_msgSender());
    }

    /**
     * @dev Returns the address of the current owner.
     */
    function owner() public view virtual returns (address) {
        return _owner;
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        require(owner() == _msgSender(), "Ownable: caller is not the owner");
        _;
    }

    /**
     * @dev Leaves the contract without owner. It will not be possible to call
     * `onlyOwner` functions anymore. Can only be called by the current owner.
     *
     * NOTE: Renouncing ownership will leave the contract without an owner,
     * thereby removing any functionality that is only available to the owner.
     */
    function renounceOwnership() public virtual onlyOwner {
        _transferOwnership(address(0));
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        _transferOwnership(newOwner);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Internal function without access restriction.
     */
    function _transferOwnership(address newOwner) internal virtual {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}

interface INFT {
    
    struct Properties {
        
        // In this example properties of the given NFT are stored
        // in a dynamically sized array of strings
        // properties can be re-defined for any specific info
        // that a particular NFT is intended to store.
        
        /* Properties could look like this:
        bytes   property1;
        bytes   property2;
        address property3;
        */
        
        string[] properties;
    }
    
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function standard() external view returns (string memory);
    function balanceOf(address _who) external view returns (uint256);
    function ownerOf(uint256 _tokenId) external view returns (address);
    function transfer(address _to, uint256 _tokenId, bytes calldata _data) external returns (bool);
    function silentTransfer(address _to, uint256 _tokenId) external returns (bool);
    
    function priceOf(uint256 _tokenId) external view returns (uint256);
    function bidOf(uint256 _tokenId) external view returns (uint256 price, address payable bidder, uint256 timestamp);
    function getTokenProperties(uint256 _tokenId) external view returns (Properties memory);
    
    function setBid(uint256 _tokenId, uint256 _amountInWEI, bytes calldata _data) payable external returns (bool);
    function withdrawBid(uint256 _tokenId) external returns (bool);
}

interface IERC721Receiver {
    /**
     * @dev Whenever an {IERC721} `tokenId` token is transferred to this contract via {IERC721-safeTransferFrom}
     * by `operator` from `from`, this function is called.
     *
     * It must return its Solidity selector to confirm the token transfer.
     * If any other value is returned or the interface is not implemented by the recipient, the transfer will be reverted.
     *
     * The selector can be obtained in Solidity with `IERC721.onERC721Received.selector`.
     */
    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external returns (bytes4);
}

abstract contract NFTReceiver {
    function nftReceived(address _from, uint256 _tokenId, bytes calldata _data) external virtual;
}

contract NFT is INFT, Ownable{

    //custom variables
    uint8 public original = 1;
    uint8 public gold     = 3;
    uint8 public silver   = 5;
    uint8 public bronz    = 10;

    uint8 public originalLeft = 1;
    uint8 public goldLeft     = 3;
    uint8 public silverLeft   = 5;
    uint8 public bronzLeft    = 10;

    address payable artist;
    string public baseURI = "https://gateway.pinata.cloud/ipfs/";
    //end custom variables
    
    using Address for address;
    
    event Transfer     (address indexed from, address indexed to, uint256 indexed tokenId);
    event TransferData (bytes data);
    
    mapping (uint256 => Properties) private _tokenProperties;
    mapping (uint32 => Fee)         public feeLevels; // level # => (fee receiver, fee percentage)
    
    uint256 public bidLock = 1 days; // Time required for a bid to become withdrawable.
    
    struct Bid {
        address payable bidder;
        uint256 amountInWEI;
        uint256 timestamp;
    }
    
    struct Fee {
        address payable feeReceiver;
        uint256 feePercentage; // Will be divided by 100000 during calculations
                               // feePercentage of 100 means 0.1% fee
                               // feePercentage of 2500 means 2.5% fee
    }
    
    mapping (uint256 => uint256) private _asks; // tokenID => price of this token (in WEI)
    mapping (uint256 => Bid)     private _bids; // tokenID => price of this token (in WEI)
    mapping (uint256 => uint32)  private _tokenFeeLevels; // tokenID => level ID / 0 by default

    // Token name
    string private _name;

    // Token symbol
    string private _symbol;

    // Mapping from token ID to owner address
    mapping(uint256 => address) private _owners;

    // Mapping owner address to token count
    mapping(address => uint256) private _balances;

    /**
     * @dev Initializes the contract by setting a `name` and a `symbol` to the token collection.
     */
    constructor(string memory name_, string memory symbol_, uint256 _defaultFee, address payable _artist)  {
        _name   = name_;
        _symbol = symbol_;
        feeLevels[0].feeReceiver   = payable(msg.sender);
        feeLevels[0].feePercentage = _defaultFee;
        //custom code
        artist = _artist;
    }
    
    modifier checkTrade(uint256 _tokenId)
    {
        _;
        (uint256 _bid, address payable _bidder,) = bidOf(_tokenId);
        if(priceOf(_tokenId) > 0 && priceOf(_tokenId) <= _bid)
        {
            uint256 _reward = _bid - _claimFee(_bid, _tokenId);
            payable(ownerOf(_tokenId)).transfer(_reward);
            delete _bids[_tokenId];
            delete _asks[_tokenId];
            _transfer(ownerOf(_tokenId), _bidder, _tokenId);
            if(address(_bidder).isContract())
            {
                NFTReceiver(_bidder).nftReceived(ownerOf(_tokenId), _tokenId, hex"000000");
            }
        }
    }
    
    function standard() public view virtual override returns (string memory)
    {
        return "NFT X";
    }
    
    function priceOf(uint256 _tokenId) public view virtual override returns (uint256)
    {
        address owner = _owners[_tokenId];
        require(owner != address(0), "NFT: owner query for nonexistent token");
        return _asks[_tokenId];
    }
    
    function bidOf(uint256 _tokenId) public view virtual override returns (uint256 price, address payable bidder, uint256 timestamp)
    {
        address owner = _owners[_tokenId];
        require(owner != address(0), "NFT: owner query for nonexistent token");
        return (_bids[_tokenId].amountInWEI, _bids[_tokenId].bidder, _bids[_tokenId].timestamp);
    }
    
    function getTokenProperties(uint256 _tokenId) public view virtual override returns (Properties memory)
    {
        return _tokenProperties[_tokenId];
    }
    
    function balanceOf(address owner) public view virtual override returns (uint256) {
        require(owner != address(0), "NFT: balance query for the zero address");
        return _balances[owner];
    }
    
    function ownerOf(uint256 tokenId) public view virtual override returns (address) {
        address owner = _owners[tokenId];
        require(owner != address(0), "NFT: owner query for nonexistent token");
        return owner;
    }
    
    function setPrice(uint256 _tokenId, uint256 _amountInWEI) checkTrade(_tokenId) public returns (bool)
    {
        require(ownerOf(_tokenId) == msg.sender, "Setting asks is only allowed for owned NFTs!");
        _asks[_tokenId] = _amountInWEI;
        return true;
    }
    
    function setBid(uint256 _tokenId, uint256 _amountInWEI, bytes calldata _data) payable checkTrade(_tokenId) public virtual override returns (bool)
    {
        (uint256 _previousBid, address payable _previousBidder, ) = bidOf(_tokenId);
        require(ownerOf(_tokenId) != msg.sender, "Can not bid for your own NFT");
        require(msg.value == _amountInWEI, "Wrong payment value provided");
        require(msg.value > _previousBid, "New bid must exceed the existing one");
        
        // Return previous bid if the current one exceeds it.
        if(_previousBid != 0)
        {
            _previousBidder.transfer(_previousBid);
        }
        _bids[_tokenId].amountInWEI = _amountInWEI;
        _bids[_tokenId].bidder      = payable(msg.sender);
        return true;
    }
    
    function withdrawBid(uint256 _tokenId) public virtual override returns (bool)
    {
        (uint256 _bid, address payable _bidder, uint256 _timestamp) = bidOf(_tokenId);
        require(msg.sender == _bidder, "Can not withdraw someone elses bid");
        require(block.timestamp > _timestamp + bidLock, "Bid is time-locked");
        
        _bidder.transfer(_bid);
        delete _bids[_tokenId];
        return true;
    }
    
    function name() public view virtual override returns (string memory) {
        return _name;
    }
    
    function symbol() public view virtual override returns (string memory) {
        return _symbol;
    }
    
    function transfer(address _to, uint256 _tokenId, bytes calldata _data) public override returns (bool)
    {
        _transfer(msg.sender, _to, _tokenId);
        if(_to.isContract())
        {
            NFTReceiver(_to).nftReceived(msg.sender, _tokenId, _data);
        }
        emit TransferData(_data);
        return true;
    }
    
    function silentTransfer(address _to, uint256 _tokenId) public override returns (bool)
    {
        _transfer(msg.sender, _to, _tokenId);
        return true;
    }
    
    function _exists(uint256 tokenId) internal view virtual returns (bool) {
        return _owners[tokenId] != address(0);
    }
    
    function _claimFee(uint256 _amountFrom, uint256 _tokenId) internal returns (uint256)
    {
        uint32  _level         = _tokenFeeLevels[_tokenId];
        address _feeReceiver   = feeLevels[_level].feeReceiver;
        uint256 _feePercentage = feeLevels[_level].feePercentage;
        
        uint256 _feeAmount = _amountFrom * _feePercentage / 100000;
        payable(_feeReceiver).transfer(_feeAmount);
        return _feeAmount;        
    }
    
    function _safeMint(
        address to,
        uint256 tokenId
    ) internal virtual {
        _mint(to, tokenId);
    }
    
    function _mint(address to, uint256 tokenId) internal virtual {
        require(to != address(0), "NFT: mint to the zero address");
        require(!_exists(tokenId), "NFT: token already minted");

        _beforeTokenTransfer(address(0), to, tokenId);

        _balances[to] += 1;
        _owners[tokenId] = to;

        emit Transfer(address(0), to, tokenId);
    }
    
    function _burn(uint256 tokenId) internal virtual {
        address owner = NFT.ownerOf(tokenId);

        _beforeTokenTransfer(owner, address(0), tokenId);
        

        _balances[owner] -= 1;
        delete _owners[tokenId];

        emit Transfer(owner, address(0), tokenId);
    }
    
    function _transfer(
        address from,
        address to,
        uint256 tokenId
    ) internal virtual {
        require(NFT.ownerOf(tokenId) == from, "NFT: transfer of token that is not own");
        require(to != address(0), "NFT: transfer to the zero address");
        
        _asks[tokenId] = 0; // Zero out price on transfer
        
        // When a user transfers the NFT to another user
        // it does not automatically mean that the new owner
        // would like to sell this NFT at a price
        // specified by the previous owner.
        
        // However bids persist regardless of token transfers
        // because we assume that the bidder still wants to buy the NFT
        // no matter from whom.

        _beforeTokenTransfer(from, to, tokenId);

        _balances[from] -= 1;
        _balances[to] += 1;
        _owners[tokenId] = to;

        emit Transfer(from, to, tokenId);
    }
    
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal virtual {}

    //Custom Code
    function buyOriginal (bytes calldata _data) external payable{
        require(msg.value >= 10000000000000000000, "Please, enter a higher amount.");
        require(originalLeft > 0, "Out of stock");
        uint8 _tokenId;
        _mint(artist, 0);
        _asks[0] = 10000000000000000000;
        _tokenProperties[0].properties.push("QmVhzs8Wfae7DWZ65TFq5SDAKYRNzcqD71Dm4bGsaSFxEs");
        _tokenProperties[_tokenId].properties.push("Fran Brych");  
        _tokenProperties[_tokenId].properties.push("This is Art");
        _tokenProperties[_tokenId].properties.push(baseURI);
        originalLeft--;
        setBid(0, msg.value, _data);
    }

    function buyGold (bytes calldata _data) external payable{
        require(msg.value >= 5000000000000000000, "Please, enter a higher amount.");
        require(goldLeft > 0, "Out of stock");
        uint8 _tokenId;
        _tokenId = gold - goldLeft + 1;
        _mint(artist, _tokenId);
        _asks[_tokenId] = 5000000000000000000;
        _tokenProperties[_tokenId].properties.push("QmVtyDeSfEx7ZiAWJkwnGSbSeVNtyLvsgqS6j8Rzg83SML");
        _tokenProperties[_tokenId].properties.push("Fran Brych");  
        _tokenProperties[_tokenId].properties.push("This is Art");
        _tokenProperties[_tokenId].properties.push(baseURI);
        goldLeft--;
        setBid(_tokenId, msg.value, _data);
    }

    function buySilver (bytes calldata _data) external payable{
        require(msg.value >= 3000000000000000000, "Please, enter a higher amount.");
        require(silverLeft > 0, "Out of stock");
        uint8 _tokenId;
        _tokenId = silver - silverLeft + 4;
        _mint(artist, _tokenId);
        _asks[_tokenId] = 3000000000000000000;
        _tokenProperties[_tokenId].properties.push("QmfB66nYwUwqtAM1f4hny6sMHaYECpeT65HRAKkqoZbewA");
        _tokenProperties[_tokenId].properties.push("Fran Brych");  
        _tokenProperties[_tokenId].properties.push("This is Art");
        _tokenProperties[_tokenId].properties.push(baseURI);
        silverLeft--;
        setBid(_tokenId, msg.value, _data);
    }

    function buyBronz (bytes calldata _data) external payable{
        require(msg.value >= 1000000000000000000, "Please, enter a higher amount.");
        require(bronzLeft > 0, "Out of stock");
        uint8 _tokenId;
        _tokenId = bronz - bronzLeft + 9;
        _mint(artist, _tokenId);
        _asks[_tokenId] = 1000000000000000000;
        _tokenProperties[_tokenId].properties.push("QmWpCGX2VeBgJc9CvTzNUCzwqECcWAbMrbbHcJdkFVLn2v");
        _tokenProperties[_tokenId].properties.push("Fran Brych");  
        _tokenProperties[_tokenId].properties.push("This is Art");
        _tokenProperties[_tokenId].properties.push(baseURI);
        bronzLeft--;
        setBid(_tokenId, msg.value, _data);
    }


    function setFeeReceiver (address _address) public onlyOwner {
        feeLevels[0].feeReceiver   = payable(_address);
    }

    function setBaseURI (string memory _baseURI) public onlyOwner {
        baseURI = _baseURI;
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public virtual {
        safeTransferFrom(from, to, tokenId, "");
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId,
        bytes memory _data
    ) public virtual {
        require(NFT.ownerOf(tokenId) == from, "NFT: transfer of token that is not own");
        _safeTransfer(from, to, tokenId, _data);
    }

    function _safeTransfer(
        address from,
        address to,
        uint256 tokenId,
        bytes memory _data
    ) internal virtual {
        _transfer(from, to, tokenId);
        require(_checkOnERC721Received(from, to, tokenId, _data), "ERC721: transfer to non ERC721Receiver implementer");
    }

    function _checkOnERC721Received(
        address from,
        address to,
        uint256 tokenId,
        bytes memory _data
    ) private returns (bool) {
        if (to.isContract()) {
            try IERC721Receiver(to).onERC721Received(msg.sender, from, tokenId, _data) returns (bytes4 retval) {
                return retval == IERC721Receiver.onERC721Received.selector;
            } catch (bytes memory reason) {
                if (reason.length == 0) {
                    revert("ERC721: transfer to non ERC721Receiver implementer");
                } else {
                    assembly {
                        revert(add(32, reason), mload(reason))
                    }
                }
            }
        } else {
            return true;
        }
    }
}