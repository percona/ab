# Copyright (C) 2000 MySQL AB & MySQL Finland AB & TCX DataKonsult AB
#
# This library is free software; you can redistribute it and/or
# modify it under the terms of the GNU Library General Public
# License as published by the Free Software Foundation; either
# version 2 of the License, or (at your option) any later version.
#
# This library is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# Library General Public License for more details.
#
# You should have received a copy of the GNU Library General Public
# License along with this library; if not, write to the Free
# Software Foundation, Inc., 59 Temple Place - Suite 330, Boston,
# MA 02111-1307, USA

## Process this file with automake to create Makefile.in

AUTOMAKE_OPTIONS = foreign

benchdir_root=		$(prefix)/mysql-bench-2
benchdir =		$(benchdir_root)
bench_SCRIPTS =		test-ATIS test-connect test-create test-insert \
			test-big-tables test-select test-wisconsin \
			test-alter-table test-transactions test-extra\
			graph-compare-results \
			bench-init.pl compare-results run-all-tests \
			server-cfg crash-me copy-db innotest1 innotest1a \
			innotest1b innotest2 innotest2a innotest2b \
			bench-count-distinct test-as3ap subquery \
                        mdl merge_locking    
CLEANFILES =		$(bench_SCRIPTS)
EXTRA_SCRIPTS =		test-ATIS.sh test-connect.sh test-create.sh \
			test-insert.sh test-big-tables.sh test-select.sh \
			test-alter-table.sh test-wisconsin.sh \
			test-transactions.sh test-extra.sh\
			bench-init.pl.sh compare-results.sh server-cfg.sh \
			run-all-tests.sh crash-me.sh copy-db.sh \
			graph-compare-results.sh innotest1.sh innotest1a.sh \
			innotest1b.sh innotest2.sh innotest2a.sh innotest2b.sh \
			bench-count-distinct.sh test-as3ap.sh misc/as3apgen/as3apgen \
			My/Timer.pm subquery.sh mdl.sh merge_locking.sh
EXTRA_DIST =		$(EXTRA_SCRIPTS)  My/Timer.pm 

SUBDIRS = misc


dist-hook:
	mkdir -p $(distdir)/Data/ATIS $(distdir)/Data/Wisconsin $(distdir)/Data/AS3AP \
		$(distdir)/limits
	for i in $(srcdir)/Data/AS3AP/*.* ; do $(INSTALL_DATA) $$i $(distdir)/Data/AS3AP ; done
	for i in $(srcdir)/Data/ATIS/*.* ; do $(INSTALL_DATA) $$i $(distdir)/Data/ATIS ; done
	for i in $(srcdir)/Data/Wisconsin/*.* ; do $(INSTALL_DATA) $$i $(distdir)/Data/Wisconsin ; done
	for i in $(srcdir)/limits/*.* ; do $(INSTALL_DATA) $$i $(distdir)/limits; done 


install-data-local:
	$(mkinstalldirs) \
		$(DESTDIR)$(benchdir)/Data \
		$(DESTDIR)$(benchdir)/Data/ATIS \
		$(DESTDIR)$(benchdir)/Data/Wisconsin \
		$(DESTDIR)$(benchdir)/Data/AS3AP \
		$(DESTDIR)$(benchdir)/limits \
		$(DESTDIR)$(benchdir)/My 
		$(INSTALL_DATA) $(srcdir)/README  $(DESTDIR)$(benchdir) 
		$(INSTALL_DATA) $(srcdir)/My/Timer.pm  $(DESTDIR)$(benchdir)/My 
	for i in $(srcdir)/Data/ATIS/*.* ; do $(INSTALL_DATA) $$i $(DESTDIR)$(benchdir)/Data/ATIS ; done
	for i in $(srcdir)/Data/Wisconsin/*.* ; do $(INSTALL_DATA) $$i $(DESTDIR)$(benchdir)/Data/Wisconsin ; done
	for i in $(srcdir)/Data/AS3AP/*.* ; do $(INSTALL_DATA) $$i $(DESTDIR)$(benchdir)/Data/AS3AP ; done
	for i in $(srcdir)/limits/*.* ; do $(INSTALL_DATA) $$i $(DESTDIR)$(benchdir)/limits; done


SUFFIXES = .sh

.sh:
	@RM@ -f $@ $@-t
	@SED@ \
	  -e 's!@''benchdir''@!$(benchdir)!g' \
	  -e 's!@''bindir''@!$(bindir)!g' \
	  -e 's!@''scriptdir''@!$(bindir)!g' \
	  -e 's!@''prefix''@!$(prefix)!g' \
	  -e 's!@''datadir''@!$(datadir)!g' \
	  -e 's!@''localstatedir''@!$(localstatedir)!g' \
	  -e 's!@''libexecdir''@!$(libexecdir)!g' \
	  -e 's!@''PERL''@!@PERL@!' \
	  $< > $@-t
	@CHMOD@ +x $@-t
	@MV@ $@-t $@

# Don't update the files from bitkeeper
%::SCCS/s.%
