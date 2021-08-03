const UnnamedToken = artifacts.require("UnnamedToken");

module.exports = function(deployer) {
  deployer.deploy(UnnamedToken);
};
