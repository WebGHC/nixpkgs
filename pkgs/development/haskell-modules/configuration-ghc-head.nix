{ pkgs, haskellLib }:

with haskellLib;

self: super: {

  # Use the latest LLVM.
  inherit (pkgs) llvmPackages;

  # Disable GHC 7.11.x core libraries.
  array = null;
  base = null;
  binary = null;
  bin-package-db = null;
  bytestring = null;
  Cabal = null;
  containers = null;
  deepseq = null;
  directory = null;
  filepath = null;
  ghc-boot = null;
  ghc-boot-th = null;
  ghc-compact = null;
  ghc-prim = null;
  ghci = null;
  haskeline = null;
  hoopl = null;
  hpc = null;
  integer-gmp = null;
  pretty = null;
  process = null;
  rts = null;
  template-haskell = null;
  terminfo = null;
  time = null;
  transformers = null;
  unix = null;
  xhtml = null;

  # jailbreak-cabal can use the native Cabal library.
  jailbreak-cabal = pkgs.haskell.packages.ghc802.jailbreak-cabal;

  # haddock: No input file(s).
  nats = dontHaddock super.nats;
  bytestring-builder = dontHaddock super.bytestring-builder;

  # We have time 1.5
  aeson = disableCabalFlag super.aeson "old-locale";

  # Show works differently for record syntax now, breaking haskell-src-exts' parser tests
  # https://github.com/haskell-suite/haskell-src-exts/issues/224
  haskell-src-exts = dontCheck super.haskell-src-exts;

  # Setup: At least the following dependencies are missing: base <4.8
  hspec-expectations = overrideCabal super.hspec-expectations (drv: {
    postPatch = "sed -i -e 's|base < 4.8|base|' hspec-expectations.cabal";
  });
  utf8-string = overrideCabal super.utf8-string (drv: {
    postPatch = "sed -i -e 's|base >= 4.3 && < 4.10|base|' utf8-string.cabal";
  });

  # bos/attoparsec#92
  attoparsec = dontCheck super.attoparsec;

  # test suite hangs silently for at least 10 minutes
  split = dontCheck super.split;

  # Test suite fails with some (seemingly harmless) error.
  # https://code.google.com/p/scrapyourboilerplate/issues/detail?id=24
  syb = dontCheck super.syb;

  # Test suite has stricter version bounds
  retry = dontCheck super.retry;

  # Test suite fails with time >= 1.5
  http-date = dontCheck super.http-date;

  happy = overrideCabal (self.callHackage "happy" "1.19.8" {}) (drv: {
    patches = [./patches/happy.patch];
  });

  # Workaround for a workaround, see comment for "ghcjs" flag.
  jsaddle = let jsaddle' = disableCabalFlag super.jsaddle "ghcjs";
            in addBuildDepends jsaddle' [ self.glib self.gtk3 self.webkitgtk3
                                          self.webkitgtk3-javascriptcore ];

  # The compat library is empty in the presence of mtl 2.2.x.
  mtl-compat = dontHaddock super.mtl-compat;

  # Won't work with LLVM 3.5.
  llvm-general = markBrokenVersion "3.4.5.3" super.llvm-general;

  # A bunch of jailbreaks due to 'base' bump
  old-time = doJailbreak super.old-time;
  old-locale = doJailbreak super.old-locale;
  primitive = self.callCabal2nix "primitive" (pkgs.fetchFromGitHub {
    owner = "haskell";
    repo = "primitive";
    rev = "db192ee76f8b49c0f6d155d1062b2cb5e956eb3e";
    sha256 = "14cb4m2705wh745i6x53wvvv7yydnlywm91rc2vm1fiacw6hbjjp";
  }) {};
  ansi-wl-pprint = self.callHackage "ansi-wl-pprint" "0.6.8.1" {};
  test-framework = dontCheck (self.callCabal2nix "test-framework" ("${pkgs.fetchFromGitHub {
    owner = "haskell";
    repo = "test-framework";
    rev = "1198e3269b67348ecc7739989b9a41ed1db7a6a2";
    sha256 = "0rkjnpxc4lrp8fpjq6c7np7yqb2jdw7dxqi9am92vqil59xf5ny1";
  }}/core") {});
  text = self.callCabal2nix "text" (pkgs.fetchFromGitHub {
    owner = "haskell";
    repo = "text";
    rev = "ccbfabedea1cf5b38ff19f37549feaf01225e537";
    sha256 = "00clz7vrsa1y4w6fnz1asl32cv48mi8jkvyba8b8yva5n6jnriw6";
  }) {};
  atomic-primops = doJailbreak (appendPatch super.atomic-primops ./patches/atomic-primops-Cabal-1.25.patch);
  hashable = doJailbreak super.hashable;
  stm = doJailbreak super.stm;
}
