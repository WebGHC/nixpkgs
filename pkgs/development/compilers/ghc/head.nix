{ stdenv, fetchgit, bootPkgs, perl, binutils, coreutils
, autoconf, automake, happy, alex, python3
, ncurses, gmp, libffi
, __targetPackages
, buildPlatform, hostPlatform, targetPlatform

, llvmPackages

, # If enabled, GHC will be build with the GPL-free but slower integer-simple
  # library instead of the faster but GPLed integer-gmp library.
  enableIntegerSimple ? targetPlatform != hostPlatform

, # If enabled, use -fPIC when compiling static libs.
  enableRelocatedStaticLibs ? targetPlatform != hostPlatform

, # TODO: Make false by default
  useVendoredLibffi ? true

, # Whether to build dynamic libs for the standard library (on the target
  # platform). Static libs are always built.
  dynamic ? let triple = targetPlatform.config;
    # On iOS, dynamic linking is not supported
    in !(stdenv.lib.strings.hasPrefix "aarch64-apple-darwin" triple)
    && !(stdenv.lib.strings.hasPrefix "arm-apple-darwin" triple)
, # Whether to use a quick build for cross compiling. This is mostly
  # just for debugging.
  quick-cross ? false
}:

let
  inherit (bootPkgs) ghc;

  version = "8.3.20170720";
  rev = "4486ab24e12ff8b0cdbb8656c89e94dd9b9940af";

  targetStdenv = __targetPackages.stdenv;
  prefix = stdenv.lib.optionalString
    (targetPlatform != hostPlatform)
    "${targetPlatform.config}-";
  underscorePrefix = stdenv.lib.optionalString
    (targetPlatform != hostPlatform)
    "${stdenv.lib.replaceStrings ["-"] ["_"] targetPlatform.config}_";

in stdenv.mkDerivation (rec {
  inherit version rev;
  name = "${prefix}ghc-${version}";

  src = fetchgit {
    url = "git://git.haskell.org/ghc.git";
    extraRemotes = ["https://github.com/WebGHC/ghc.git"];
    inherit rev;
    sha256 = "13xd7mxg34fdznmpx0f52sn682qhjl2l5h3ag3j11zddcq8wkv5r";
  };

  postPatch = "patchShebangs .";

  #v p dyn
  preConfigure = stdenv.lib.optionalString (targetPlatform != hostPlatform)''
    sed 's|#BuildFlavour  = quick-cross|BuildFlavour  = ${if quick-cross then "quick" else "perf"}-cross|' mk/build.mk.sample > mk/build.mk
    echo 'Stage1Only = YES' >> mk/build.mk
  '' + stdenv.lib.optionalString (targetPlatform != hostPlatform && dynamic) ''
    echo 'DYNAMIC_GHC_PROGRAMS = YES' >> mk/build.mk
  '' + stdenv.lib.optionalString enableRelocatedStaticLibs ''
    echo 'GhcLibHcOpts += -fPIC' >> mk/build.mk
    echo 'GhcRtsHcOpts += -fPIC' >> mk/build.mk
  '' /* + stdenv.lib.optionalString prebuiltAndroidTarget ''
    echo 'EXTRA_CC_OPTS += -std=gnu99' >> mk/build.mk
  '' */ + stdenv.lib.optionalString enableIntegerSimple ''
    echo "INTEGER_LIBRARY = integer-simple" >> mk/build.mk
  '' + ''
    echo ${version} >VERSION
    echo ${rev} >GIT_COMMIT_ID
    ./boot
    sed -i -e 's|-isysroot /Developer/SDKs/MacOSX10.5.sdk||' configure
  '' +
    ( if targetPlatform.isDarwin
      then ''
        export NIX_LDFLAGS+=" -no_dtrace_dof"
      '' else ''
        export NIX_LDFLAGS="$NIX_LDFLAGS -rpath $out/lib/ghc-${version}"
      ''); # perf-cross

  nativeBuildInputs = stdenv.lib.optionals (targetPlatform != hostPlatform) [
    ghc perl autoconf automake happy alex python3
    ncurses.dev
  ] ++ stdenv.lib.optionals (!enableIntegerSimple && targetPlatform != hostPlatform) [
    gmp.dev
  ] ++ stdenv.lib.optionals (!useVendoredLibffi) [
    libffi.dev
  ];

  buildInputs = stdenv.lib.optionals (targetPlatform == hostPlatform) [
    ghc perl autoconf automake happy alex python3
  ] ++ stdenv.lib.optionals (targetPlatform != hostPlatform) [
    targetStdenv.cc

    # Stringly speaking, LLVM is only needed for platforms the native
    # code generator does not support, but using it when
    # cross-compiling anywhere.
    llvmPackages.llvm

    ncurses.dev __targetPackages.ncurses.dev
  ] ++ stdenv.lib.optionals (!enableIntegerSimple && targetPlatform != hostPlatform) [
    gmp.dev __targetPackages.gmp.dev
  ] ++ stdenv.lib.optionals (!useVendoredLibffi) [
    libffi.dev __targetPackages.libffi.dev
  ];

  propagatedBuildInputs = stdenv.lib.optionals (targetPlatform != hostPlatform) [
    ncurses.out __targetPackages.ncurses.out
  ] ++ stdenv.lib.optionals (!enableIntegerSimple && targetPlatform != hostPlatform) [
    gmp.out __targetPackages.gmp.out
  ] ++ stdenv.lib.optionals (!useVendoredLibffi) [
    libffi.out __targetPackages.libffi.out
  # ] ++ stdenv.lib.optionals (prebuiltAndroidTarget || targetPlatform != hostPlatform && targetPlatform.libc == "libsystem") [
  #   __targetPackages.libiconv
  ];

  # Hack so that envHooks are run for build inputs and crossEnvHooks for host
  # inputs. In the future stdenv's setup.sh will be changed to avoid this need.
  crossConfig = if targetPlatform != hostPlatform then "hack" else null;

  enableParallelBuilding = true;

  configureFlags = [
    "CC=${targetStdenv.cc or stdenv.cc}/bin/${prefix}cc"
  # TODO: With Cross rebuild (need to fix hooks) remove these `--with-*` altogether
  ] ++ stdenv.lib.optionals (targetPlatform == hostPlatform) [
    "--with-curses-includes=${__targetPackages.ncurses.dev}/include"
    "--with-curses-libraries=${__targetPackages.ncurses.out}/lib"
  ] ++ stdenv.lib.optionals (targetPlatform == hostPlatform && !enableIntegerSimple) [
    "--with-gmp-includes=${__targetPackages.gmp.dev}/include"
    "--with-gmp-libraries=${__targetPackages.gmp.out}/lib"
  ] ++ stdenv.lib.optionals (targetPlatform == hostPlatform && targetPlatform.isDarwin) [
    "--with-iconv-includes=${__targetPackages.libiconv}/include"
    "--with-iconv-libraries=${__targetPackages.libiconv}/lib"
  ] ++ stdenv.lib.optionals (targetPlatform != hostPlatform) [

    # TODO: next rebuild make these unconditional
    #"--build=x86_64-unknown-linux-gnu"#${buildPlatform.config}"
    #"--host=x86_64-unknown-linux-gnu"#${hostPlatform.config}"
    "--target=${targetPlatform.config}"

    "--enable-bootstrap-with-devel-snapshot"
    "--verbose"
    #"--with-system-libffi"
  ] ++ stdenv.lib.optionals (targetPlatform.config == "aarch64-apple-darwin14") [
    # fix for iOS: https://www.reddit.com/r/haskell/comments/4ttdz1/building_an_osxi386_to_iosarm64_cross_compiler/d5qvd67/
    "--disable-large-address-space"
  ];

  # required, because otherwise all symbols from HSffi.o are stripped, and
  # that in turn causes GHCi to abort
  stripDebugFlags = [ "-S" ] ++ stdenv.lib.optional (!targetPlatform.isDarwin) "--keep-file-symbols";

  checkTarget = "test";

  # zsh and other shells are smart about `{ghc}` but bash isn't, and doesn't
  # treat that as a unary `{x,y,z,..}` repetition.
  postInstall = ''
    paxmark m $out/lib/${name}/bin/${if targetPlatform != hostPlatform then "ghc" else "{ghc,haddock}"}

    # Install the bash completion file.
    install -D -m 444 utils/completion/ghc.bash $out/share/bash-completion/completions/${prefix}ghc

    # Patch scripts to include "readelf" and "cat" in $PATH.
    for i in "$out/bin/"*; do
      test ! -h $i || continue
      egrep --quiet '^#!' <(head -n 1 $i) || continue
      sed -i -e '2i export PATH="$PATH:${stdenv.lib.makeBinPath [ binutils coreutils ]}"' $i
    done
  '';

  passthru = {
    inherit bootPkgs;

    inherit llvmPackages;
  };

  meta = {
    homepage = "http://haskell.org/ghc";
    description = "The Glasgow Haskell Compiler";
    maintainers = with stdenv.lib.maintainers; [ marcweber andres peti ];
    inherit (ghc.meta) license platforms;
  };

  # TODO: next mass rebuild / version bump just do
  # dontSetConfigureCross = buildPlatform != targetPlatform;
# } // stdenv.lib.optionalAttrs prebuiltAndroidTarget {

#   # It gets confused with ncurses
#   dontPatchELF = true;
#   dontCrossPatchELF = true;

#   # It uses the native strip on libraries too
#   dontStrip = true;
#   dontCrossStrip = true;

#   # Hack so we can get away with not stripping and patching.
#   noAuditTmpdir = true;

#   patches = [
#     ./android-patches/add-llvm-target-data-layout.patch
#     #./android-patches/build-deps-extra-cc-opts.patch
#     ./android-patches/unix-posix_vdisable.patch
#     #./android-patches/unix-posix-files-imports.patch
#     ./android-patches/enable-fPIC.patch
#     ./android-patches/no-pthread-android.patch
#     ./android-patches/force_CC_SUPPORTS_TLS_equal_zero.patch
#     ./android-patches/undefine_MYTASK_USE_TLV_for_CC_SUPPORTS_TLS_zero.patch
#     ./android-patches/force-relocation-equal-pic.patch
#     ./android-patches/rts_android_log_write.patch
#     ./android-patches/patch_rts_elf.patch

#     ./android-patches/extra-modules-temp.patch
#     ./android-patches/pthread-die-temp.patch
#   ];
# } // stdenv.lib.optionalAttrs (buildPlatform != targetPlatform && targetPlatform.libc or "" == "libSystem") {
#   patches = [
#     ./android-patches/enable-fPIC.patch
#   ];
})
