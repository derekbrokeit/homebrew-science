require 'formula'

class Lammps < Formula
  homepage 'http://lammps.sandia.gov'
  url 'http://lammps.sandia.gov/tars/lammps-12Feb13.tar.gz'
  sha1 'e4c1cc179e8159e7bd2dd958d3f5c8909a315af8'
  # lammps releases are named after their release date. We transform it to
  # YYYY.MM.DD (year.month.day) so that we get a comparable version numbering (for brew outdated)
  version '2013.02.12'
  head 'http://git.icms.temple.edu/lammps-ro.git'

  # user-submitted packages not considered "standard"
  # 'user-omp' must be last
  USER_PACKAGES= %W[
    user-misc
    user-awpmd
    user-cg-cmm
    user-colvars
    user-eff
    user-molfile
    user-reaxc
    user-sph
    user-omp
  ]

  # could not get gpu or user-cuda to install (hardware problem?)
  # kim requires openkim software, which is not currently in homebrew.
  # user-atc would not install without mpi and then would not link to blas-lapack
  DISABLED_PACKAGES = %W[
    gpu
    kim
  ]
  DISABLED_USER_PACKAGES = %W[
    user-atc
    user-cuda
  ]

  # setup user-packages as options
  USER_PACKAGES.each do |package|
    option "enable-#{package}", "Build lammps with the '#{package}' package"
  end

  # additional options
  option "with-mpi", "Build lammps with MPI support"

  depends_on 'fftw'
  depends_on 'jpeg'
  depends_on 'voro++'
  depends_on MPIDependency.new(:cxx, :f90) if build.include? "with-mpi"
  depends_on 'homebrew/dupes/gcc' if build.include? "enable-user-omp"

  def build_lib(comp, lmp_lib, opts={})
    non_std_repl = opts[:non_std_repl]  # a non-standard compiler name to replace
    var_add = opts[:var_add] || ""      # prepended to makefile variable names

    cd "lib/"+lmp_lib do
      if comp == "FC"
        make_file = "Makefile.gfortran" # make file
        repl = "F90"                    # replace compiler
      elsif comp == "CXX"
        make_file = "Makefile.g++"      # make file
        repl = "CC"                     # replace compiler
        repl = non_std_repl if non_std_repl
      elsif comp == "MPICXX"
        make_file = "Makefile.openmpi"  # make file
        repl = "CC"                     # replace compiler
        comp = "CXX"                    # Reduntant since this returns to MPICXX
      end

      compiler = ENV[comp]
      if build.include? "with-mpi"
        compiler = ENV["MPI" + comp]
      end

      # force compiler
      inreplace make_file do |s|
        s.change_make_var! repl, compiler
      end

      system "make", "-f", make_file

      if File.exists? "Makefile.lammps"
        # empty it to reduce chance of conflicts
        inreplace "Makefile.lammps" do |s|
          s.change_make_var! var_add+lmp_lib+"_SYSINC", ""
          s.change_make_var! var_add+lmp_lib+"_SYSLIB", ""
          s.change_make_var! var_add+lmp_lib+"_SYSPATH", ""
        end
      end
    end
  end

  def install
    ENV.j1      # not parallel safe (some packages have race conditions :meam:)
    ENV.fortran # we need fortran for many packages, so just bring it along

    # make sure to optimize the installation
    ENV.append "CFLAGS","-O"
    ENV.append "LDFLAGS","-O"

    if build.include? "enable-user-omp"
      # OpenMP requires the latest gcc
      ENV["CXX"] = Formula.factory('homebrew/dupes/gcc').opt_prefix/"bin/g++"

      # The following should be part of MPIDependency mxcl/homebrew#17370
      ENV["OMPI_MPICXX"] = ENV["CXX"]              # correct the openmpi wrapped compiler
      # mpich2 needs this, but it would throw an error without mpich2. Therefore, I leave it out
      # ENV.append "CFLAGS", "-CC=#{ENV['CXX']}"     # mpich2   wrapped compiler

      # Build with OpenMP
      ENV.append "CFLAGS",  "-fopenmp"
      ENV.append "LDFLAGS", "-L#{Formula.factory('homebrew/dupes/gcc').opt_prefix}/gcc/lib -lgomp"
    end

    # build package libraries
    build_lib "FC",    "reax"
    build_lib "FC",    "meam"
    build_lib "CXX",   "poems"
    build_lib "CXX",   "colvars", :non_std_repl => "CXX"  if build.include? "enable-user-colvars"
    if build.include? "enable-user-awpmd" and build.include? "with-mpi"
      build_lib "MPICXX","awpmd",   :var_add => "user-"
      ENV.append 'LDFLAGS', "-lblas -llapack"
    end

    # we currently assume gfortran is our fortran library
    ENV.append 'LDFLAGS', "-L#{Formula.factory('gfortran').opt_prefix}/gfortran/lib -lgfortran"

    # build the lammps program and library
    cd "src" do
      # setup the make file variabls for fftw, jpeg, and mpi
      inreplace "MAKE/Makefile.mac" do |s|
        # We will stick with "make mac" type and forget about
        # "make mac_mpi" because it has some unnecessary
        # settings. We get a nice clean slate with "mac"
        if build.include? "with-mpi"
          # compiler info
          s.change_make_var! "CC"     , ENV["MPICXX"]
          s.change_make_var! "LINK"   , ENV["MPICXX"]

          #-DOMPI_SKIP_MPICXX is to speed up c++ compilation
          s.change_make_var! "MPI_INC"  , "-DOMPI_SKIP_MPICXX"
          s.change_make_var! "MPI_PATH" , ""
          s.change_make_var! "MPI_LIB"  , ""
        else
          s.change_make_var! "CC"   , ENV["CXX"]
          s.change_make_var! "LINK" , ENV["CXX"]
        end

        # installing with FFTW and JPEG
        s.change_make_var! "FFT_INC"  , "-DFFT_FFTW3 -I#{Formula.factory('fftw').opt_prefix}/include"
        s.change_make_var! "FFT_PATH" , "-L#{Formula.factory('fftw').opt_prefix}/lib"
        s.change_make_var! "FFT_LIB"  , "-lfftw3"

        s.change_make_var! "JPG_INC"  , "-DLAMMPS_JPEG -I#{Formula.factory('jpeg').opt_prefix}/include"
        s.change_make_var! "JPG_PATH" , "-L#{Formula.factory('jpeg').opt_prefix}/lib"
        s.change_make_var! "JPG_LIB"  , "-ljpeg"

        s.change_make_var! "CCFLAGS", ENV["CFLAGS"]
        s.change_make_var! "LIB", ENV["LDFLAGS"]
      end

      inreplace "VORONOI/Makefile.lammps" do |s|
        s.change_make_var! "voronoi_SYSINC", "-I#{HOMEBREW_PREFIX}/include/voro++"
      end

      # setup standard packages
      system "make", "yes-standard"
      DISABLED_PACKAGES.each do |pkg|
        system "make", "no-" + pkg
      end

      # setup optional packages
      USER_PACKAGES.each do |pkg|
        system "make", "yes-" + pkg if build.include? "enable-" + pkg
      end

      unless build.include? "with-mpi"
        # build fake mpi library
        cd "STUBS" do
          system "make"
        end
      end

      system "make", "mac"
      mv "lmp_mac", "lammps" # rename it to make it easier to find

      # build the lammps library
      system "make", "makeshlib"
      system "make", "-f", "Makefile.shlib", "mac"

      # install them
      bin.install("lammps")
      lib.install("liblammps_mac.so")
      lib.install("liblammps.so") # this is just a soft-link to liblamps_mac.so

    end

    # get the python module
    cd "python" do
      temp_site_packages = lib/which_python/'site-packages'
      mkdir_p temp_site_packages
      ENV['PYTHONPATH'] = temp_site_packages

      system "python", "install.py", lib, temp_site_packages
      mv "examples", "python-examples"
      prefix.install("python-examples")
    end

    # install additional materials
    (share/'lammps').install(["doc", "potentials", "tools", "bench"])
  end

  def which_python
    "python" + `python -c 'import sys;print(sys.version[:3])'`.strip
  end

  def test
    # to prevent log files, move them to a temporary directory
    mktemp do
      system "lammps","-in","#{HOMEBREW_PREFIX}/share/lammps/bench/in.lj"
      system "python","-c","from lammps import lammps ; lammps().file('#{HOMEBREW_PREFIX}/share/lammps/bench/in.lj')"
    end
  end

  def caveats
    <<-EOS.undent
    You should run a benchmark test or two. There are plenty available.

      cd #{HOMEBREW_PREFIX}/share/lammps/bench
      lammps -in in.lj
      # with mpi
      mpiexec -n 2 lammps -in in.lj

    The following directories could come in handy

      Documentation:
      #{HOMEBREW_PREFIX}/share/lammps/doc/Manual.html

      Potential files:
      #{HOMEBREW_PREFIX}/share/lammps/potentials

      Python examples:
      #{HOMEBREW_PREFIX}/share/lammps/python-examples

      Additional tools (may require manual installation):
      #{HOMEBREW_PREFIX}/share/lammps/tools

    To use the Python module with non-homebrew Python, you need to amend your
    PYTHONPATH like so:
      export PYTHONPATH=#{HOMEBREW_PREFIX}/lib/python2.7/site-packages:$PYTHONPATH

    EOS
  end

  # This fixes the python module to point to the absolute path of the lammps library
  # without this the module cannot find the library when homebrew is installed in a
  # custom directory.
  def patches
    p = [ DATA,]
    # user-omp has a bug because it assumes gnu
    # patch submitted upstream, USER-OMP is currently being rewritten as a standard package and this patch may soon become obsolete
    p << "https://gist.github.com/scicalculator/4759616/raw/3b9b1ad9b38f0f20a52e63e8c7add9780056b2ca/user-omp_bsd.patch" if build.include? "enable-user-omp"
    p
  end
end

__END__
diff --git a/python/lammps.py b/python/lammps.py
index c65e84c..b2b28a2 100644
--- a/python/lammps.py
+++ b/python/lammps.py
@@ -23,8 +23,8 @@ class lammps:
     # if name = "g++", load liblammps_g++.so
 
     try:
-      if not name: self.lib = CDLL("liblammps.so",RTLD_GLOBAL)
-      else: self.lib = CDLL("liblammps_%s.so" % name,RTLD_GLOBAL)
+      if not name: self.lib = CDLL("HOMEBREW_PREFIX/lib/liblammps.so",RTLD_GLOBAL)
+      else: self.lib = CDLL("HOMEBREW_PREFIX/lib/liblammps_%s.so" % name,RTLD_GLOBAL)
     except:
       type,value,tb = sys.exc_info()
       traceback.print_exception(type,value,tb)
