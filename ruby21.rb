class Ruby21 < Formula
  desc "Powerful, clean, object-oriented scripting language"
  homepage "https://www.ruby-lang.org/"
  url "https://cache.ruby-lang.org/pub/ruby/2.1/ruby-2.1.10.tar.bz2"
  sha256 "a74675578a9a801ac25eb7152bef3023432d6267f875b198eb9cd6944a5bf4f1"

  bottle do
    sha256 "5399d1d3f8cbaaf3eccba8e45a215732a9885fe38367e63114ea272c468968e0" => :sierra
    sha256 "8df5a7cf1a836bdb492f4042bacadcae5de9f180787f141b4a7eb546f0dc9f51" => :el_capitan
    sha256 "39bee040951dded7f2d07fd9810bf57b1ff1c9b756b34b0fec9a330b78e7b149" => :yosemite
  end

  keg_only :provided_by_osx

  option :universal
  option "with-suffix", "Suffix commands with '21'"
  option "with-doc", "Install documentation"
  option "with-tcltk", "Install with Tcl/Tk support"

  depends_on "pkg-config" => :build
  depends_on "readline" => :recommended
  depends_on "gdbm" => :optional
  depends_on "gmp" => :optional
  depends_on "libffi" => :optional
  depends_on "libyaml"
  depends_on "openssl"
  depends_on :x11 if build.with? "tcltk"

  fails_with :llvm do
    build 2326
  end

  def install
    args = %W[
      --prefix=#{prefix}
      --enable-shared
      --disable-silent-rules
      --with-sitedir=#{HOMEBREW_PREFIX}/lib/ruby/site_ruby
      --with-vendordir=#{HOMEBREW_PREFIX}/lib/ruby/vendor_ruby
    ]

    if build.universal?
      ENV.universal_binary
      args << "--with-arch=#{Hardware::CPU.universal_archs.join(",")}"
    end

    args << "--program-suffix=#{program_suffix}" if build.with? "suffix"
    args << "--with-out-ext=tk" if build.without? "tcltk"
    args << "--disable-install-doc" if build.without? "doc"
    args << "--disable-dtrace" unless MacOS::CLT.installed?
    args << "--without-gmp" if build.without? "gmp"

    # Reported upstream: https://bugs.ruby-lang.org/issues/10272
    args << "--with-setjmp-type=setjmp" if MacOS.version == :lion

    paths = [
      Formula["libyaml"].opt_prefix,
      Formula["openssl"].opt_prefix,
    ]

    %w[readline gdbm gmp libffi].each do |dep|
      paths << Formula[dep].opt_prefix if build.with? dep
    end

    args << "--with-opt-dir=#{paths.join(":")}"

    system "./configure", *args

    # Ruby has been configured to look in the HOMEBREW_PREFIX for the
    # sitedir and vendordir directories; however we don't actually want to create
    # them during the install.
    #
    # These directories are empty on install; sitedir is used for non-rubygems
    # third party libraries, and vendordir is used for packager-provided libraries.
    inreplace "tool/rbinstall.rb" do |s|
      s.gsub! 'prepare "extension scripts", sitelibdir', ""
      s.gsub! 'prepare "extension scripts", vendorlibdir', ""
      s.gsub! 'prepare "extension objects", sitearchlibdir', ""
      s.gsub! 'prepare "extension objects", vendorarchlibdir', ""
    end

    system "make"
    system "make", "install"
  end

  def post_install
    # Customize rubygems to look/install in the global gem directory
    # instead of in the Cellar, making gems last across reinstalls
    config_file = lib/"ruby/#{abi_version}/rubygems/defaults/operating_system.rb"
    config_file.unlink if config_file.exist?
    config_file.write rubygems_config

    # Create the sitedir and vendordir that were skipped during install
    ruby="#{bin}/ruby#{program_suffix}"
    %w[sitearchdir vendorarchdir].each do |dir|
      mkdir_p `#{ruby} -rrbconfig -e 'print RbConfig::CONFIG["#{dir}"]'`
    end

    # Create the version-specific bindir used by rubygems
    mkdir_p rubygems_bindir
  end

  def abi_version
    "2.1.0"
  end

  def program_suffix
    build.with?("suffix") ? "21" : ""
  end

  def rubygems_bindir
    "#{HOMEBREW_PREFIX}/lib/ruby/gems/#{abi_version}/bin"
  end

  def rubygems_config; <<-EOS.undent
    module Gem
      class << self
        alias :old_default_dir :default_dir
        alias :old_default_path :default_path
        alias :old_default_bindir :default_bindir
        alias :old_ruby :ruby
      end

      def self.default_dir
        path = [
          "#{HOMEBREW_PREFIX}",
          "lib",
          "ruby",
          "gems",
          "#{abi_version}"
        ]

        @default_dir ||= File.join(*path)
      end

      def self.private_dir
        path = if defined? RUBY_FRAMEWORK_VERSION then
                 [
                   File.dirname(RbConfig::CONFIG['sitedir']),
                   'Gems',
                   RbConfig::CONFIG['ruby_version']
                 ]
               elsif RbConfig::CONFIG['rubylibprefix'] then
                 [
                  RbConfig::CONFIG['rubylibprefix'],
                  'gems',
                  RbConfig::CONFIG['ruby_version']
                 ]
               else
                 [
                   RbConfig::CONFIG['libdir'],
                   ruby_engine,
                   'gems',
                   RbConfig::CONFIG['ruby_version']
                 ]
               end

        @private_dir ||= File.join(*path)
      end

      def self.default_path
        if Gem.user_home && File.exist?(Gem.user_home)
          [user_dir, default_dir, private_dir]
        else
          [default_dir, private_dir]
        end
      end

      def self.default_bindir
        "#{rubygems_bindir}"
      end

      def self.ruby
        "#{opt_bin}/ruby#{program_suffix}"
      end
    end
    EOS
  end

  def caveats; <<-EOS.undent
    By default, binaries installed by gem will be placed into:
      #{rubygems_bindir}

    You may want to add this to your PATH.
    EOS
  end

  test do
    hello_text = shell_output("#{bin}/ruby#{program_suffix} -e 'puts :hello'")
    assert_equal "hello\n", hello_text
    system "#{bin}/gem#{program_suffix}", "list", "--local"
  end
end
