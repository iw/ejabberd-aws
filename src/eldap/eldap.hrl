%%%----------------------------------------------------------------------
%%%
%%% ejabberd, Copyright (C) 2002-2009   ProcessOne
%%%
%%% This program is free software; you can redistribute it and/or
%%% modify it under the terms of the GNU General Public License as
%%% published by the Free Software Foundation; either version 2 of the
%%% License, or (at your option) any later version.
%%%
%%% This program is distributed in the hope that it will be useful,
%%% but WITHOUT ANY WARRANTY; without even the implied warranty of
%%% MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
%%% General Public License for more details.
%%%
%%% You should have received a copy of the GNU General Public License
%%% along with this program; if not, write to the Free Software
%%% Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA
%%% 02111-1307 USA
%%%
%%%----------------------------------------------------------------------

-define(LDAP_PORT, 389).
-define(LDAPS_PORT, 636).

-record(eldap_search, {scope = wholeSubtree,
		       base = [],
		       filter,
		       limit = 0,
		       attributes = [],
		       types_only = false,
		       timeout = 0}).


-record(eldap_search_result, {entries,
			      referrals}).

-record(eldap_entry, {object_name,
		      attributes}).
