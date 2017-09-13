{ fetchFromGitHub }:

# Use builtins.fetchTarball "https://github.com/commercialhaskell/all-cabal-hashes/archive/hackage.tar.gz"
# instead if you want the latest Hackage automatically at the price of frequent re-downloads.

fetchFromGitHub {
  owner = "commercialhaskell";
  repo = "all-cabal-hashes";
  rev = "ab21c23c0b45432103177e1a47d7a277b6e6b8ce";
  sha256 = "0ivkzj7f0a2abqrqn2q3mp3ddifddinf7w2wyf8r58h1cwh5xsls";
}
