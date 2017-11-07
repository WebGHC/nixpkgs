{ stdenv, __targetPackages
, buildPlatform, hostPlatform, targetPlatform

# build-tools
, bootPkgs, alex, happy
, autoconf, automake, binutils, coreutils, fetchgit, perl, python3
, clang ? null, gcc ? null

, libffi, libiconv ? null, ncurses

, # LLVM is conceptually a run-time-only depedendency, but for
  # non-x86, we need LLVM to bootstrap later stages, so it becomes a
  # build-time dependency too.
  llvmPackages

, # If enabled, GHC will be build with the GPL-free but slower integer-simple
  # library instead of the faster but GPLed integer-gmp library.
  enableIntegerSimple ? false, gmp ? null

, # If enabled, use -fPIC when compiling static libs.
  enableRelocatedStaticLibs ? targetPlatform != hostPlatform

, # Whether to build dynamic libs for the standard library (on the target
  # platform). Static libs are always built.
  enableShared ?
    !(targetPlatform.isDarwin
      # On iOS, dynamic linking is not supported
      && (targetPlatform.isAarch64 || targetPlatform.isArm))

, version ? "8.3.20170808"

, quick-cross ? false

, with-terminfo ? true
}:

assert !enableIntegerSimple -> gmp != null;

let
  inherit (bootPkgs) ghc;

  rev = "14457cf6a50f708eecece8f286f08687791d51f7";

  # TODO(@Ericson2314) Make unconditional
  prefix = stdenv.lib.optionalString
    (targetPlatform != hostPlatform)
    "${targetPlatform.config}-";

  buildMK = ''
    DYNAMIC_GHC_PROGRAMS = ${if enableShared then "YES" else "NO"}
  '' + stdenv.lib.optionalString enableIntegerSimple ''
    INTEGER_LIBRARY = integer-simple
  '' + stdenv.lib.optionalString (targetPlatform != hostPlatform) ''
    BuildFlavour = ${if quick-cross then "quick" else "perf"}-cross
    Stage1Only = YES
    HADDOCK_DOCS = NO
    BUILD_SPHINX_HTML = NO
    BUILD_SPHINX_PDF = NO
  '' + stdenv.lib.optionalString (!with-terminfo) ''
    WITH_TERMINFO = NO
  '' + stdenv.lib.optionalString enableRelocatedStaticLibs ''
    GhcLibHcOpts += -fPIC
    GhcRtsHcOpts += -fPIC
  '' + stdenv.lib.optionalString prebuiltAndroidTarget ''
    EXTRA_CC_OPTS += -std=gnu99
  '';

  prebuiltAndroidTarget = targetPlatform.useAndroidPrebuilt or false;

  # Splicer will pull out correct variations
  libDeps = platform: stdenv.lib.optional with-terminfo ncurses
    ++ stdenv.lib.optional (!enableIntegerSimple) gmp
    ++ stdenv.lib.optional (platform.libc != "glibc") libiconv;

  targetCC =
    if hostPlatform == buildPlatform
    then __targetPackages.stdenv.cc
    else assert targetPlatform == hostPlatform;
      # build != host == target
      stdenv.cc;
in
stdenv.mkDerivation rec {
  inherit version rev;
  name = "${prefix}ghc-${version}";

  src = fetchgit {
    url = "git://git.haskell.org/ghc.git";
    inherit rev;
    sha256 = "08vj9ca7rq7rv8pjfl14fg2lg9d6zisrwlq6bi5vzr006816dy8y";
  };

  enableParallelBuilding = true;

  outputs = [ "out" "doc" ];

  postPatch = "patchShebangs .";

  # It gets confused with ncurses
  dontPatchELF = prebuiltAndroidTarget;

  # It uses the native strip on libraries too
  dontStrip = prebuiltAndroidTarget;

  # Hack so we can get away with not stripping and patching.
  noAuditTmpdir = prebuiltAndroidTarget;

  # GHC is a bit confused on its cross terminology.
  preConfigure = ''
    for env in $(env | grep '^TARGET_' | sed -E 's|\+?=.*||'); do
      export "''${env#TARGET_}=''${!env}"
    done
    echo -n "${buildMK}" > mk/build.mk
    echo ${version} >VERSION
    echo ${rev} >GIT_COMMIT_ID
    ./boot
    sed -i -e 's|-isysroot /Developer/SDKs/MacOSX10.5.sdk||' configure
  '' + stdenv.lib.optionalString (!stdenv.isDarwin) ''
    export NIX_LDFLAGS+=" -rpath $out/lib/ghc-${version}"
  '' + stdenv.lib.optionalString stdenv.isDarwin ''
    export NIX_LDFLAGS+=" -no_dtrace_dof"
  '';

  # TODO(@Ericson2314): Always pass "--target" and always prefix.
  configurePlatforms = [ "build" "host" ]
    ++ stdenv.lib.optional (targetPlatform != hostPlatform) "target";
  # `--with` flags for libraries needed for RTS linker
  configureFlags = [
    # GHC is a bit confused on its cross terminology, as these would normally be
    # the *host* tools. Also, passing these on the command line seems to have a
    # different effect that merely defining them.
    "CC=${targetCC}/bin/${targetCC.prefix}cc"
    "LD=${targetCC.binutils}/bin/${targetCC.prefix}ld"
    "AS=${targetCC.binutils.binutils}/bin/${targetCC.prefix}as"
    "AR=${targetCC.binutils.binutils}/bin/${targetCC.prefix}ar"
    "NM=${targetCC.binutils.binutils}/bin/${targetCC.prefix}nm"
    "RANLIB=${targetCC.binutils.binutils}/bin/${targetCC.prefix}ranlib"
    "READELF=${targetCC.binutils.binutils}/bin/${targetCC.prefix}readelf"
    "STRIP=${targetCC.binutils.binutils}/bin/${targetCC.prefix}strip"
    "--datadir=$doc/share/doc/ghc"
  ] ++ stdenv.lib.optionals (with-terminfo) [
    "--with-curses-includes=${ncurses.dev}/include" "--with-curses-libraries=${ncurses.out}/lib"
  ] ++ stdenv.lib.optional (targetPlatform == hostPlatform && ! enableIntegerSimple) [
    "--with-gmp-includes=${gmp.dev}/include" "--with-gmp-libraries=${gmp.out}/lib"
  ] ++ stdenv.lib.optional (targetPlatform == hostPlatform && hostPlatform.libc != "glibc") [
    "--with-iconv-includes=${libiconv}/include" "--with-iconv-libraries=${libiconv}/lib"
  ] ++ stdenv.lib.optionals (targetPlatform != hostPlatform) [
    "--enable-bootstrap-with-devel-snapshot"
  ] ++ stdenv.lib.optionals (targetPlatform.isDarwin && targetPlatform.isAarch64) [
    # fix for iOS: https://www.reddit.com/r/haskell/comments/4ttdz1/building_an_osxi386_to_iosarm64_cross_compiler/d5qvd67/
    "--disable-large-address-space"
  ];

  nativeBuildInputs = [ ghc perl autoconf automake happy alex python3 ];

  # For building runtime libs
  __depsBuildTarget = [ targetCC ];

  buildInputs = libDeps hostPlatform;

  propagatedBuildInputs = [
    (if hostPlatform == buildPlatform
     then __targetPackages.stdenv.cc
     else (if hostPlatform.isDarwin then clang else gcc))
  ] # Stringly speaking, LLVM is only needed for platforms the native
    # code generator does not support, but using it when
    # cross-compiling anywhere.]
    ++ stdenv.lib.optional (targetPlatform != hostPlatform) llvmPackages.llvm;

  __depsTargetTarget = map stdenv.lib.getDev (libDeps targetPlatform);
  __depsTargetTargetPropagated = map (stdenv.lib.getOutput "out") (libDeps targetPlatform);

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
    inherit bootPkgs prefix;

    inherit llvmPackages;
  };

  meta = {
    homepage = http://haskell.org/ghc;
    description = "The Glasgow Haskell Compiler";
    maintainers = with stdenv.lib.maintainers; [ marcweber andres peti ];
    inherit (ghc.meta) license platforms;
  };

}
