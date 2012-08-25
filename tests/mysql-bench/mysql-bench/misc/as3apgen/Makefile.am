CPPFLAGS = -D_GNU_SOURCE -DAS3APGEN_VERSION=\"0.9.6\"
as3apgendir = ${prefix}/mysql-bench-2/misc/as3apgen
as3apgen_PROGRAMS = as3apgen
as3apgen_SOURCES = as3apgen.cc
as3apgen_LDADD = @LIBS@
EXTRA_DIST = as3apgen.cc as3apgen.h
AUTOMAKE_OPTIONS = foreign

# Don't update the files from bitkeeper
%::SCCS/s.%

