


contract FNFTManager is ERC721 {
    address public immutable factory;

    constructor(address factoryAddress)
        ERC721("UniswapV3 NFT Positions", "UNIV3")
    {
        factory = factoryAddress;
    }

    function tokenURI(uint256 tokenId)
        public
        view
        override
        returns (string memory)
    {
        return "";
    }
}