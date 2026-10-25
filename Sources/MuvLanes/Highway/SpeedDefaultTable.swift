/// The legal speeds of muv-osm (`lanes/highway/speed_default.rs`, which
/// muv-generate makes from the OSM wiki's default speed limits), as data:
/// for each road class (`urban`, `rural`, `motorway`, ...) and region, the
/// minimum and the maximum speeds per mode and condition. Generated from
/// that file by a throwaway script, as one text (a string literal compiles
/// at once, where dictionary literals of this size cost a release build
/// half a minute), decoded by `SpeedDefault`. Lines, fields split by tabs:
/// `R` and a date range the conditions refer to by index; `F`, a Rust
/// function's name and its two maps; `D`, a class, a region and the
/// function; `C`, a class and the dispatch function `default` calls.
///
/// A map is `mode=restriction;...` per mode, the two maps split by `|`, a
/// restriction a number and a unit (`k` km/h, `m` mph, `w` walk; `t`, `p`,
/// `s` tonne, pound, short ton; `M`, `f` metre, foot), its conditions after
/// `@` joined by `&` (`T` trailer, `C` caravan, `A` articulated, `W` wet,
/// `D<n>` the n-th date range, an operator `>`, `g` (>=), `<`, `l` (<=) or
/// `=` with the compared measure). Do not edit by hand.
///
/// This Source Code Form is subject to the terms of the Mozilla Public
/// License, v. 2.0. If a copy of the MPL was not distributed with this
/// file, You can obtain one at https://mozilla.org/MPL/2.0/.

extension SpeedDefault {
    static let table = #"""
R	sunset-sunrise
R	Nov-Mar
R	Nov-Mar
R	Dec-Feb
R	Dec-Feb
R	Dec-Feb
R	(sunset+01:30)-(sunrise-01:30)
R	(sunset+00:30)-(sunrise-00:30)
R	sunset-sunrise
F	living_street_ad	|All=20k
F	urban_ad	|All=50k
F	motorroad_ad	|All=120k
F	motorway_ad	|All=120k
F	service_ae	|All=25k
F	rural_ae	|All=100k,Hgv=80k,Bus=80k,SchoolBus=80k
F	motorway_ae	All=60k|All=120k,Hgv=80k,Bus=80k,SchoolBus=80k
F	urban_ag	|All=20m,Goods=15m,Bus=15m
F	rural_ag	|All=40m,Goods=25m,Bus=25m
F	urban_al	|All=40k,Hgv=35k@T;35k@A,Bus=35k@>Weightrating:8t,Hazmat=30k
F	rural_al	|All=80k,Hgv=70k;70k@T;70k@A;60k@>Weightrating:12t,Bus=70k@>Weightrating:8t,TruckBus=70k@>Weightrating:5t,Hazmat=50k
F	motorway_al	|All=110k,Hgv=90k;80k@T;80k@A;80k@>Weightrating:12t,Bus=90k@>Weightrating:8t,TruckBus=80k@>Weightrating:5t,Hazmat=50k
F	living_street_am	|All=20k
F	urban_am	|All=60k;70k@T,Motorcycle=90k,Coach=90k,Hgv=70k,Minibus=90k,Bus=70k,SchoolBus=60k
F	rural_am	|All=90k;70k@T,Motorcycle=90k,Coach=90k,Hgv=70k,Minibus=90k,Bus=70k,SchoolBus=60k
F	motorway_am	|All=110k;90k@T,Motorcycle=90k,Coach=90k,Hgv=90k,Minibus=90k,Bus=90k,SchoolBus=60k
F	urban_ao	|All=60k;50k@T,Motorcycle=60k;50k@T,Goods=60k;50k@T,Hgv=50k;50k@A;40k@T,AutoRickshaw=50k,Bus=50k;40k@T
F	rural_ao	|All=90k;70k@T,Motorcycle=90k;70k@T,Goods=80k;70k@T,Hgv=80k;80k@A;70k@T,AutoRickshaw=70k,Bus=80k;70k@T
F	motorroad_ao	|All=100k;80k@T,Motorcycle=100k;80k@T,Goods=90k;80k@T,Hgv=80k;70k@A;70k@T,AutoRickshaw=80k,Bus=90k;80k@T
F	motorway_ao	All=40k|All=120k;100k@T,Motorcycle=120k;100k@T,Goods=110k;90k@T,Hgv=90k;90k@A;80k@T,AutoRickshaw=100k,Bus=100k;90k@T
F	rural_ar	|All=110k;80k@C,Motorcycle=110k,Motorhome=90k,Goods=110k,Hgv=80k,Bus=90k,Hazmat=80k
F	motorway_ar	All=65k|All=130k;80k@C,Motorcycle=130k,Motorhome=100k,Goods=110k,Hgv=80k,Bus=100k,Hazmat=80k
F	urban_as	|All=15m
F	rural_as	|All=25m
F	living_street_at	|All=1w
F	urban_at	|All=50k;80k@T;70k@>Weightrating:3.5t,Hgv=70k,Bus=80k;70k@A
F	rural_at	|All=100k;80k@T;70k@>Weightrating:3.5t,Hgv=70k,Bus=80k;70k@A
F	motorroad_at	|All=100k;100k@T;80k@>Weightrating:3.5t,Hgv=80k,Bus=100k;80k@A
F	motorway_at	|All=130k;100k@T;80k@>Weightrating:3.5t,Hgv=80k,Bus=100k;80k@A
F	urban_au	|All=50k
F	rural_au	|All=100k
F	urban_au_act	|All=50k
F	rural_au_act	|All=100k;100k@>Weightrating:12t,Bus=100k@>Weightrating:5t
F	urban_au_nsw	|All=50k
F	rural_au_nsw	|All=100k;100k@>Weightrating:4.5t
F	urban_au_nt	|All=50k
F	rural_au_nt	|All=110k;100k@>Weightrating:12t,Bus=100k@>Weightrating:5t
F	urban_au_qld	|All=50k
F	rural_au_qld	|All=100k;100k@>Weightrating:12t,Hgv=90k@T;90k@A,Bus=100k@>Weightrating:5t
F	urban_au_sa	|All=50k
F	rural_au_sa	|All=100k;100k@>Weightrating:12t,Bus=100k@>Weightrating:5t
F	urban_au_tas	|All=50k
F	urban_au_vic	|All=50k
F	rural_au_vic	|All=100k;100k@>Weightrating:12t,Hgv=100k@A&>Weightrating:22t,Bus=100k@>Weightrating:5t
F	urban_au_wa	|All=50k
F	rural_au_wa	|All=110k;100k@>Weightrating:12t;100k@T,Bus=100k@>Weightrating:5t
F	urban_aw	|All=50k
F	rural_aw	|All=80k
F	service_az	|All=20k
F	living_street_az	|All=20k
F	urban_az	|All=60k,TruckBus=50k
F	rural_az	|All=90k,Motorcycle=90k,Coach=90k,Goods=90k,Hgv=70k,Minibus=90k,Bus=70k,TruckBus=50k
F	motorway_az	All=50k|All=110k,Motorcycle=90k,Coach=90k,Goods=110k,Hgv=90k,Minibus=90k,Bus=90k,TruckBus=50k
F	living_street_ba	|All=1w
F	urban_ba	|All=50k;80k@T,Hgv=80k;70k@>Weightrating:7.5t;70k@T,Bus=80k;70k@A,SchoolBus=70k
F	rural_ba	|All=80k;80k@T,Hgv=80k;70k@>Weightrating:7.5t;70k@T,Bus=80k;70k@A,SchoolBus=70k
F	motorroad_ba	|All=100k;80k@T,Hgv=80k;70k@>Weightrating:7.5t;70k@T,Bus=80k;70k@A,SchoolBus=70k
F	motorway_ba	All=40k|All=130k;80k@T,Hgv=80k;70k@>Weightrating:7.5t;70k@T,Bus=100k;70k@A,SchoolBus=70k
F	living_street_be_bru	|All=20k
F	urban_be_bru	|All=30k
F	rural_be_bru	|All=70k
F	motorway_be_bru	|All=120k;90k@>Weightrating:3.5t,Coach=100k,Bus=90k
F	living_street_be_vlg	|All=20k
F	urban_be_vlg	|All=50k
F	rural_be_vlg	|All=70k
F	motorway_be_vlg	|All=120k;90k@>Weightrating:3.5t,Coach=100k,Bus=90k
F	living_street_be_wal	|All=20k
F	urban_be_wal	|All=50k
F	rural_be_wal	|All=90k
F	motorway_be_wal	|All=120k;90k@>Weightrating:3.5t,Coach=100k,Bus=90k
F	urban_bf	|All=50k
F	rural_bf	|All=90k;90k@>Weightrating:10t,Bus=90k,Hazmat=60k@>Weightrating:12t
F	living_street_bg	|All=20k
F	urban_bg	|All=50k,Motorcycle=50k,Hgv=50k,Bus=50k,Hazmat=40k
F	rural_bg	|All=90k;80k@>Weightrating:3.5t;70k@T,Motorcycle=80k,Hgv=80k;70k@T;70k@A,Bus=80k;70k@T,Hazmat=50k
F	motorroad_bg	All=50k|All=120k;90k@>Weightrating:3.5t;90k@T,Motorcycle=90k,Hgv=90k,Bus=90k,Hazmat=90k
F	motorway_bg	All=50k|All=140k;100k@>Weightrating:3.5t;100k@T,Motorcycle=100k,Hgv=100k,Bus=100k,Hazmat=90k
F	urban_bh	|All=60k,Motorcycle=50k,Goods=50k,Bus=50k
F	rural_bh	|All=100k,Motorcycle=80k,Goods=80k,Bus=80k
F	urban_bi	|All=50k,Bus=40k
F	rural_bi	|All=80k;50k@>Weightrating:10t,Bus=70k
F	urban_bj	|All=50k,Hazmat=50k@>Weightrating:12t
F	motorway_bj	|All=110k,Hgv=90k@>Weightrating:10t,Hazmat=60k@>Weightrating:12t
F	urban_bn	|All=60k
F	rural_bn	|All=75k@T,Goods=80k;75k@>Weightrating:7.5t;75k@T;75k@A,Bus=80k;75k@T
F	urban_bo	|All=40k
F	urban_bs	|All=25m
F	rural_bs	|All=45m
F	urban_bs_np	|All=25m
F	rural_bs_np	|All=30m
F	urban_bt	|All=30k
F	rural_bt	|All=50k,Motorcycle=50k,Goods=50k;35k@>Weightrating:3t,Bus=35k
F	living_street_bw	|All=30k
F	urban_bw	|All=60k;80k@T;80k@>Weightrating:3.5t,Motorcycle=60k@T,Hgv=80k,Bus=80k;100k@>Length:10M;100k@gSeats:15;80k@T;80k@A,SchoolBus=80k
F	rural_bw	|All=100k;80k@T;80k@>Weightrating:3.5t,Motorcycle=60k@T,Hgv=80k,Bus=80k;100k@>Length:10M;100k@gSeats:15;80k@T;80k@A,SchoolBus=80k
F	living_street_by	|All=20k
F	urban_by	|All=60k
F	rural_by	|All=90k;70k@T,Motorcycle=90k,Hgv=70k,Bus=90k;70k@T,TruckBus=60k
F	motorway_by	|All=110k;90k@T,Motorcycle=90k,Hgv=90k,Bus=90k,TruckBus=60k
F	rural_ca_ab	|All=80k
F	urban_ca_bc	|All=50k
F	rural_ca_bc	|All=80k
F	urban_ca_mb	|All=50k
F	rural_ca_mb	|All=90k
F	urban_ca_nb	|All=50k
F	rural_ca_nb	|All=80k
F	urban_ca_nl	|All=50k
F	rural_ca_nl	|All=80k
F	rural_ca_ns	|All=80k
F	urban_ca_nt	|All=50k
F	rural_ca_nt	|All=90k
F	urban_ca_nu	|All=50k
F	rural_ca_nu	|All=90k
F	urban_ca_on	|All=50k
F	rural_ca_on	|All=80k
F	urban_ca_pe	|All=50k
F	rural_ca_pe	|All=100k;90k@D0
F	urban_ca_qc	|All=50k
F	rural_ca_qc	|All=90k
F	urban_cd	|All=60k
F	rural_cd	|All=90k,Bus=75k
F	motorway_cd	All=60k|All=120k;90k@>Weightrating:7.5t,Bus=90k
F	urban_cf	|All=60k;40k@>Weightrating:3.5t
F	rural_cf	|All=110k;90k@>Weightrating:3.5t;60k@>Weightrating:12.5t;60k@>TrailerWeight:0.75t,Bus=90k;60k@>Weightrating:12.5t;60k@>TrailerWeight:0.75t
F	urban_cg	|All=60k;40k@>Weightrating:3.5t
F	rural_cg	|All=110k;90k@>Weightrating:3.5t;60k@>Weightrating:12.5t;60k@>TrailerWeight:0.75t,Bus=90k;60k@>Weightrating:12.5t;60k@>TrailerWeight:0.75t
F	living_street_ch	|All=20k
F	urban_ch	|All=50k;80k@T,Hgv=80k;80k@T;80k@A
F	rural_ch	|All=80k;80k@T,Hgv=80k;80k@T;80k@A
F	motorroad_ch	All=80k|All=100k;80k@T,Motorhome=100k,Hgv=80k;80k@T;80k@A,Bus=100k;80k@T
F	motorway_ch	All=80k|All=120k;80k@T,Motorhome=100k,Hgv=80k;80k@T;80k@A,Bus=100k;80k@T
F	urban_ci	|All=70k,Hgv=50k,Bus=50k
F	rural_ci	|All=110k,Hgv=90k;80k@>Weightrating:16t,Bus=90k
F	motorway_ci	|All=120k,Hgv=90k;80k@>Weightrating:16t,Bus=90k
F	urban_cl	|All=50k
F	rural_cl	|All=100k,Coach=100k,Hgv=100k;90k@>Weightrating:3.86t,Bus=90k,SchoolBus=90k
F	urban_cm	|All=60k;40k@>Weightrating:3.5t
F	rural_cm	|All=110k;90k@>Weightrating:3.5t;60k@>Weightrating:12t;60k@>TrailerWeight:0.75t,Bus=90k;60k@>Weightrating:12.5t;60k@>TrailerWeight:0.75t
F	urban_cn	|All=50k
F	motorway_cn	All=60k|All=120k,Motorcycle=80k,Motorhome=100k,Goods=100k,Bus=100k
F	urban_co	|All=50k
F	rural_co	|All=90k,Goods=80k,Bus=80k
F	motorway_co	|All=120k,Goods=80k,Bus=80k
F	urban_cr	|All=50k
F	rural_cr	|All=60k
F	service_cu	|All=20k
F	urban_cu	|All=50k
F	rural_cu	|All=90k;70k@T,Goods=80k;70k@T
F	motorway_cu	|All=100k;80k@T,Goods=90k;80k@T
F	urban_cv	|All=50k,Hgv=50k;40k@T
F	rural_cv	|All=90k;80k@>Weightrating:3.5t;70k@T,Goods=80k;70k@T,Hgv=80k;70k@T,AutoRickshaw=70k
F	motorroad_cv	|All=100k;90k@>Weightrating:3.5t;90k@>Weightrating:3.5t&T;80k@T,Goods=90k;70k@T,Hgv=80k;70k@T,AutoRickshaw=80k
F	motorway_cv	All=60k|All=120k;100k@>Weightrating:3.5t;100k@T;90k@>Weightrating:3.5t&T,Goods=110k;90k@T,Hgv=90k;80k@T,AutoRickshaw=100k
F	urban_cw	|All=40k
F	rural_cw	|All=60k
F	motorroad_cw	All=40k|All=80k
F	urban_cy	|All=30m,Hazmat=40k
F	living_street_cz	|All=20k
F	urban_cz	|All=50k
F	rural_cz	|All=90k;80k@>Weightrating:3.5t,Bus=90k
F	living_street_de	|All=1w
F	urban_de	|All=50k
F	rural_de	|All=100k;80k@T;80k@>Weightrating:3.5t;60k@>Weightrating:7.5t,Motorhome=80k;60k@>Weightrating:7.5t,Hgv=80k;60k@>Weightrating:7.5t,Bus=80k;60k@>Weightrating:7.5t;60k@T
F	motorway_de	All=60k|All=infk;80k@T;80k@>Weightrating:3.5t,Motorcycle=60k@T,Motorhome=80k@T,Coach=100k;60k@T,Hgv=80k;60k@gTrailers:2,Bus=80k;60k@T
F	living_street_dk	|All=15k
F	urban_dk	|All=50k;80k@T;80k@>Weightrating:3.5t,Hgv=80k,Bus=80k;80k@>Weightrating:3.5t
F	rural_dk	|All=80k;80k@T;80k@>Weightrating:3.5t,Hgv=80k,Bus=80k;80k@>Weightrating:3.5t
F	motorroad_dk	|All=80k;80k@T;80k@>Weightrating:3.5t,Hgv=80k,Bus=80k;80k@>Weightrating:3.5t
F	motorway_dk	All=50k|All=130k;80k@T;80k@>Weightrating:3.5t,Coach=100k,Hgv=80k,Bus=130k;80k@>Weightrating:3.5t
F	urban_do	|All=35k
F	rural_do	|All=60k;50k@>Weightcapacity:2t;50k@>Emptyweight:2t,Bus=50k,Hazmat=50k
F	urban_ec	|All=50k,Bus=40k
F	rural_ec	|All=100k,Hgv=70k;50k@T,Bus=90k
F	living_street_ee	|All=20k
F	urban_ee	|All=50k,TruckBus=60k
F	rural_ee	|All=90k;50k@T,TruckBus=60k
F	urban_eg	|All=60k
F	living_street_es	|All=20k
F	urban_es	|All=30k,AutoRickshaw=70k
F	rural_es	|All=90k;80k@T;80k@A,Motorhome=80k@>Weightrating:3.5t,Hgv=80k,AutoRickshaw=70k,Bus=80k,SchoolBus=80k,Hazmat=70k
F	motorway_es	All=60k|All=120k;90k@T;90k@A,Motorhome=90k@>Weightrating:3.5t,Hgv=90k,AutoRickshaw=70k,Minibus=100k,Bus=80k,SchoolBus=90k,Hazmat=80k
F	living_street_fi	|All=20k
F	urban_fi	|All=50k;80k@T,Motorhome=100k,Coach=100k,Goods=100k,Hgv=80k,Bus=80k
F	rural_fi	|All=100k;80k@T,Motorhome=100k,Coach=100k,Goods=100k,Hgv=80k,Bus=80k
F	urban_fj	|All=50k;60k@T;50k@>TrailerWeight:2.035t,Goods=60k@>Weight:2.035t;50k@>Weight:2.035t&T;60k@>Weight:2.035t&>TrailerWeight:2.035t;40k@>Weight:3.05t&T;60k@>Weight:3.05t&>TrailerWeight:1.525t;25k@gTrailers:2,Bus=60k
F	rural_fj	|All=80k;60k@T;50k@>TrailerWeight:2.035t,Goods=60k@>Weight:2.035t;50k@>Weight:2.035t&T;60k@>Weight:2.035t&>TrailerWeight:2.035t;40k@>Weight:3.05t&T;60k@>Weight:3.05t&>TrailerWeight:1.525t;25k@gTrailers:2,Bus=60k
F	urban_fm_ksa	|All=20m
F	rural_fm_ksa	|All=25m
F	urban_fm_trk	|All=20m
F	rural_fm_trk	|All=25m
F	urban_fm_yap	|All=20m
F	rural_fm_yap	|All=25m
F	living_street_fr	|All=20k
F	urban_fr	|All=50k,Hgv=70k,Bus=80k@>Weightrating:3.5t,Hazmat=70k;60k@>Weightrating:12t
F	rural_fr	|All=80k;80k@W;60k@T&>Weightrating:12t;60k@A&>Weightrating:12t,Hgv=90k;80k@>Weightrating:12t,Bus=80k@>Weightrating:3.5t,Hazmat=60k@>Weightrating:12t
F	motorway_fr	|All=130k;110k@W;90k@>Weightrating:3.5t,Coach=100k,Hgv=90k,Bus=100k;110k@>Weightrating:3.5t;90k@>Weightrating:10t,Hazmat=80k@>Weightrating:12t
F	urban_ga	|All=60k;40k@>Weightrating:3.5t
F	rural_ga	|All=110k;90k@>Weightrating:3.5t;60k@>Weightrating:12.5t;60k@>TrailerWeight:0.75t,Bus=90k;60k@>Weightrating:12.5t;60k@>TrailerWeight:0.75t
F	nsl_restricted_gb	|All=30m;50m@T;20m@gTrailers:2,Motorhome=60m;50m@>Emptyweight:3.05t,Hgv=50m,Bus=50m
F	nsl_single_gb	|All=60m;50m@T;20m@gTrailers:2,Motorhome=60m;50m@>Emptyweight:3.05t,Hgv=50m,Bus=50m
F	nsl_dual_gb	|All=70m;60m@T;20m@gTrailers:2,Motorhome=70m;60m@>Emptyweight:3.05t,Hgv=60m,Bus=60m
F	motorway_gb	|All=70m;60m@T;40m@gTrailers:2,Motorhome=70m,Hgv=70m;60m@>Weightrating:7.5t;60m@A,Bus=70m;60m@>Length:12M
F	nsl_restricted_gb_sct	|All=30m;50m@T;20m@gTrailers:2,Motorhome=60m;50m@>Emptyweight:3.05t,Hgv=50m;40m@>Weightrating:7.5t,Bus=50m
F	nsl_single_gb_sct	|All=60m;50m@T;20m@gTrailers:2,Motorhome=60m;50m@>Emptyweight:3.05t,Hgv=50m;40m@>Weightrating:7.5t,Bus=50m
F	nsl_dual_gb_sct	|All=70m;60m@T;20m@gTrailers:2,Motorhome=70m;60m@>Emptyweight:3.05t,Hgv=60m;50m@>Weightrating:7.5t,Bus=60m
F	motorway_gb_sct	|All=70m;60m@T;40m@gTrailers:2,Motorhome=70m,Hgv=70m;60m@>Weightrating:7.5t;60m@A,Bus=70m;60m@>Length:12M
F	urban_gd	|All=20m
F	rural_gd	|All=40m,Goods=35m,Bus=35m
F	living_street_ge	|All=20k
F	urban_ge	|All=60k;70k@>Weightrating:3.5t;80k@T;70k@>TrailerWeight:0.75t,Motorcycle=80k,Minibus=80k,Bus=70k,TruckBus=60k
F	rural_ge	|All=90k;70k@>Weightrating:3.5t;80k@T;70k@>TrailerWeight:0.75t,Motorcycle=80k,Minibus=80k,Bus=70k,TruckBus=60k
F	motorway_ge	|All=110k;80k@>Weightrating:3.5t;80k@T;70k@>TrailerWeight:0.75t;80k@>Weightrating:3.5t&>TrailerWeight:0.75t,Motorcycle=80k,Minibus=80k,Bus=80k,TruckBus=60k
F	urban_gh	|All=50k
F	rural_gh	|All=90k,Hgv=75k,Bus=80k
F	motorway_gh	|All=100k,Hgv=75k,Bus=80k
F	urban_gq	|All=60k;40k@>Weightrating:3.5t
F	rural_gq	|All=110k;90k@>Weightrating:3.5t;60k@>Weightrating:12.5t;60k@>TrailerWeight:0.75t,Bus=90k;60k@>Weightrating:12.5t;60k@>TrailerWeight:0.75t
F	urban_gr	|All=50k
F	rural_gr	|All=90k;80k@T,Hgv=80k;70k@A;70k@T,Bus=80k
F	motorroad_gr	|All=110k;90k@T,Hgv=80k;70k@A;70k@T,Bus=90k
F	motorway_gr	|All=130k;80k@T,Hgv=85k;80k@A;80k@T,Bus=100k
F	urban_gy	|All=30m
F	rural_gy	|All=40m,Hgv=40m,Bus=40m
F	living_street_hr	|All=1w
F	urban_hr	|All=50k
F	rural_hr	|All=90k;80k@T;80k@>Weightrating:3.5t,Bus=80k;70k@A,SchoolBus=80k
F	motorroad_hr	All=60k|All=110k;80k@T;80k@>Weightrating:3.5t,Bus=80k;70k@A,SchoolBus=80k
F	motorway_hr	All=80k|All=130k;90k@T;90k@>Weightrating:3.5t,Bus=100k,SchoolBus=80k
F	urban_ht	|All=50k
F	living_street_hu	|All=20k
F	urban_hu	|All=50k,Hgv=70k,AutoRickshaw=40k,Bus=70k
F	rural_hu	|All=90k;70k@>Weightrating:3.5t;70k@T,Hgv=70k,AutoRickshaw=40k,Bus=70k
F	motorroad_hu	All=60k|All=110k;70k@>Weightrating:3.5t;70k@T,Hgv=70k,Bus=70k
F	motorway_hu	All=60k|All=130k;80k@>Weightrating:3.5t;80k@T,Hgv=80k,Bus=100k
F	urban_id	|All=50k
F	urban_ie	|All=50k;80k@>Weightrating:3.5t;80k@T,Hgv=80k,Bus=80k
F	rural_ie	|All=80k;80k@>Weightrating:3.5t;80k@T,Hgv=80k,Bus=80k
F	motorway_ie	|All=120k;80k@>Weightrating:3.5t;80k@T,Hgv=90k,Bus=100k
F	living_street_il	|All=30k
F	urban_il	|All=50k,Hgv=80k@>Weightrating:12t
F	rural_il	|All=80k,Hgv=80k@>Weightrating:12t
F	motorway_il	|All=110k,Hgv=80k@>Weightrating:12t,Minibus=110k,Bus=100k
F	living_street_im	|All=20m
F	urban_im	|All=30m;20m@gTrailers:2;40m@T;40m@>Weightrating:32.52t&A;20m@gTrailers:2,Motorhome=60m;50m@>Weightrating:3.5t,Goods=60m,Hgv=50m;40m@>Weightrating:7.5t,Minibus=50m,Bus=40m
F	rural_im	|All=60m;40m@T;40m@>Weightrating:32.52t&A;20m@gTrailers:2,Motorhome=60m;50m@>Weightrating:3.5t,Goods=60m,Hgv=50m;40m@>Weightrating:7.5t,Minibus=50m,Bus=40m
F	urban_in	|All=70k,Motorcycle=60k,Goods=60k,AutoRickshaw=50k,Bus=60k
F	rural_in	|All=70k,Motorcycle=60k,Goods=60k,AutoRickshaw=50k,Bus=60k
F	motorway_in	|All=120k,Motorcycle=80k,Goods=80k,Bus=100k
F	living_street_is	|All=10k
F	urban_is	|All=50k
F	rural_is	|All=80k
F	urban_it	|All=50k,Hazmat=30k
F	rural_it	|All=90k;80k@>Weightrating:3.5t;70k@>Weightrating:12t,Hgv=80k;70k@>Weightrating:12t;70k@T;70k@A,Bus=80k@>Weightrating:8t;70k@A,TruckBus=70k@>Weightrating:5t,Hazmat=50k
F	motorway_it	|All=130k;110k@W;100k@>Weightrating:3.5t;100k@>Weightrating:12t,Hgv=100k;80k@>Weightrating:12t;80k@T;80k@A,Bus=100k@>Weightrating:8t;80k@A,TruckBus=80k@>Weightrating:5t,Hazmat=50k
F	motorway_jp	|All=100k,Hgv=80k,AutoRickshaw=80k,Bus=100k;80k@>Weightrating:8t
F	urban_ke	|All=50k;80k@A;65k@T,Goods=80k;65k@T,Bus=80k;65k@T
F	rural_ke	|All=100k;80k@A;65k@T,Goods=80k;65k@T,Bus=80k;65k@T
F	urban_kg	|All=60k
F	rural_kg	|All=90k;70k@>Weightrating:3.5t;70k@T,Motorcycle=90k,Coach=90k,Minibus=90k,Bus=70k,TruckBus=60k
F	motorway_kg	|All=110k;90k@>Weightrating:3.5t;70k@T,Motorcycle=90k,Coach=90k,Minibus=90k,Bus=90k,TruckBus=60k
F	urban_kh	|All=60k,Hazmat=40k
F	rural_kh	|All=100k,Hgv=80k,AutoRickshaw=70k,Hazmat=70k
F	urban_ki	|All=40k;30k@>Emptyweight:5t;30k@T
F	rural_ki	|All=60k;30k@>Emptyweight:5t;30k@T
F	urban_kn	|All=20m
F	rural_kn	|All=40m,Goods=30m,Bus=30m
F	urban_kr	|All=50k
F	rural_kr	|All=60k
F	motorroad_kr	All=50k|All=80k
F	motorway_kr	All=50k|All=80k
F	living_street_kz	|All=20k
F	urban_kz	|All=60k,TruckBus=60k
F	rural_kz	|All=110k;70k@T,Coach=90k,Goods=90k,Hgv=70k,Minibus=90k,Bus=70k,SchoolBus=70k,TruckBus=60k
F	motorway_kz	|All=140k;90k@T,Coach=110k,Goods=110k,Hgv=90k,Minibus=110k,Bus=90k,SchoolBus=90k,TruckBus=60k
F	urban_li	|All=50k
F	rural_li	|All=80k
F	urban_lr	|All=25m
F	rural_lr	|All=45m,Motorcycle=40m
F	urban_ls	|All=60k,Hgv=80k@>Weightrating:9t,Bus=100k
F	rural_ls	|All=100k;80k@A&>Weightrating:9t,Hgv=80k@>Weightrating:9t,Bus=100k
F	motorway_ls	|All=120k;80k@A&>Weightrating:9t,Hgv=80k@>Weightrating:9t,Bus=100k
F	living_street_lt	|All=20k
F	urban_lt	|All=50k
F	rural_lt	|All=90k;80k@>Weightrating:3.5t,Hgv=80k,Bus=80k
F	motorroad_lt	All=60k|All=120k;110k@D1;90k@T;90k@>Weightrating:3.5t,Hgv=90k,Bus=90k
F	motorway_lt	All=60k|All=130k;110k@D2;90k@>Weightrating:3.5t;90k@T,Hgv=90k,Bus=100k;90k@T
F	living_street_lu	|All=20k
F	urban_lu	|All=50k
F	rural_lu	|All=90k;75k@>Weightrating:7.5t;75k@T;75k@A,Bus=75k
F	motorway_lu	All=40k|All=130k;110k@W;90k@>Weightrating:7.5t;90k@T;90k@A;75k@>Weightrating:12t,Bus=90k;75k@>Weightrating:12t
F	living_street_lv	|All=20k
F	urban_lv	|All=50k,TruckBus=60k
F	rural_lv	|All=90k;80k@T,Hgv=80k@>Weightrating:7.5t,TruckBus=60k
F	motorroad_lv	|All=110k;90k@D3;90k@T,Hgv=110k;90k@D4;90k@>Weightrating:7.5t,Bus=100k;90k@D5,TruckBus=60k
F	living_street_md	|All=20k
F	urban_md	|All=50k,Hazmat=40k
F	rural_md	|All=90k;70k@T,Coach=90k,Hgv=70k,Minibus=90k,Bus=70k,TruckBus=60k,Hazmat=70k
F	motorroad_md	All=60k|All=110k;90k@T,Motorcycle=90k,Coach=90k,Hgv=90k,Minibus=90k,Bus=90k,TruckBus=60k,Hazmat=70k
F	urban_mh	|All=25m
F	rural_mh	|All=40m
F	urban_mk	|All=50k
F	rural_mk	|All=90k;80k@T,Goods=80k;70k@T;70k@>Weightrating:7.5t,Bus=80k;70k@A,SchoolBus=70k,TruckBus=50k,Hazmat=60k
F	motorroad_mk	All=60k|All=110k;80k@T,Goods=80k;70k@T;70k@>Weightrating:7.5t,Bus=80k;70k@A,SchoolBus=70k,TruckBus=50k,Hazmat=60k
F	motorway_mk	All=60k|All=130k;80k@T,Goods=100k;90k@>Weightrating:3.5t;80k@>Weightrating:7.5t,Bus=100k,SchoolBus=70k,TruckBus=50k,Hazmat=60k
F	urban_mm	|All=30m;20m@T
F	rural_mm	|All=50m
F	living_street_mn	|All=20k
F	urban_mn	|All=60k,SchoolBus=50k
F	rural_mn	|All=80k;60k@T,SchoolBus=50k
F	urban_ms	|All=20m,Goods=15m,Bus=15m
F	rural_ms	|All=40m,Goods=25m,Bus=25m
F	urban_mt	|All=50k,Goods=40k;30k@>Weightrating:3t,Bus=40k
F	rural_mt	|All=80k,Goods=60k;40k@>Weightrating:3t,Bus=60k
F	urban_mw	|All=50k,Goods=80k@>Weightrating:9t,Bus=90k;80k@gSeats:28;80k@A
F	rural_mw	|All=80k,Goods=80k@>Weightrating:9t,Bus=90k;80k@gSeats:28;80k@A
F	living_street_mx	|All=20k
F	service_mx	|All=20k
F	pedestrian_mx	|All=20k
F	urban_mx	|All=50k
F	rural_mx	|All=80k
F	urban_mz	|All=60k,Motorcycle=50k
F	rural_mz	|All=120k;100k@T,Motorcycle=90k;70k@T,Goods=100k,AutoRickshaw=70k,Bus=100k
F	urban_na	|All=60k,Goods=80k@>Weightrating:9t,Bus=100k
F	rural_na	|All=100k,Goods=80k@>Weightrating:9t,Bus=100k
F	motorway_na	|All=120k,Goods=80k@>Weightrating:9t,Bus=100k
F	urban_ne	|All=50k
F	motorway_ne	|All=110k,Goods=90k@>Weightrating:9t,Hazmat=60k@>Weightrating:12t
F	urban_ng	|All=50k,Hgv=45k
F	rural_ng	|All=80k,Motorcycle=50k,Hgv=50k
F	motorway_ng	|All=100k,Hgv=60k,Bus=90k
F	urban_ni	|All=45k
F	rural_ni	|All=60k
F	living_street_nl	|All=15k
F	urban_nl	|All=50k,Motorhome=80k@>Weightrating:3.5t,Coach=100k,Hgv=80k,Bus=80k
F	rural_nl	|All=80k,Motorhome=80k@>Weightrating:3.5t,Coach=100k,Hgv=80k,Bus=80k
F	urban_nl_bq1	|All=40k
F	rural_nl_bq1	|All=60k
F	urban_nl_bq2	|All=20k
F	rural_nl_bq2	|All=40k
F	urban_nl_bq3	|All=30k
F	rural_nl_bq3	|All=50k
F	living_street_no	|All=1w
F	urban_no	|All=50k;80k@>Weightrating:7.5t;80k@T,Goods=80k@>Weightrating:3.5t,Hgv=80k,Bus=80k@>Weightrating:3.5t
F	rural_no	|All=80k;80k@>Weightrating:7.5t;80k@T,Goods=80k@>Weightrating:3.5t,Hgv=80k,Bus=80k@>Weightrating:3.5t
F	motorway_no	|All=110k;80k@>Weightrating:7.5t;80k@T,Coach=100k,Goods=80k@>Weightrating:3.5t,Hgv=80k,Bus=80k@>Weightrating:3.5t
F	urban_np	|All=40k
F	rural_np	|All=80k,Motorcycle=50k,Goods=70k,Minibus=80k,Bus=70k
F	living_street_nz	|All=10k
F	urban_nz	|All=50k
F	rural_nz	|All=100k;90k@>Weightrating:3.5t;90k@T,SchoolBus=80k@>Weightrating:2t
F	urban_pa	|All=40k,Hazmat=40k
F	rural_pa	|All=100k,Hazmat=80k
F	motorway_pa	|All=120k,Hazmat=80k
F	urban_pe	|All=40k
F	rural_pe	|All=60k
F	urban_pg	|All=60k
F	rural_pg	|All=100k
F	urban_ph	|All=30k
F	urban_pk	|All=55k;50k@T,Motorcycle=70k,Goods=80k;50k@>Weightrating:2.268t;25k@T;25k@>Weightrating:10.2t,AutoRickshaw=30k,Bus=70k;65k@gSeats:15
F	rural_pk	|All=70k;50k@T,Motorcycle=70k,Goods=80k;50k@>Weightrating:2.268t;25k@T;25k@>Weightrating:10.2t,AutoRickshaw=30k,Bus=70k;65k@gSeats:15
F	living_street_pl	|All=20k
F	urban_pl	|All=50k
F	rural_pl	|All=90k;70k@>Weightrating:3.5t;70k@T,Bus=70k
F	motorway_pl	All=40k|All=140k;80k@>Weightrating:3.5t;80k@T,Coach=100k,Bus=80k
F	urban_pr	|All=25m;15m@>Weightrating:10000p,Bus=15m,Hazmat=15m
F	rural_pr	|All=45m;35m@>Weightrating:10000p,Bus=35m,Hazmat=30m
F	motorway_pr	|All=65m;55m@>Weightrating:10000p,Bus=55m,Hazmat=30m
F	urban_ps	|All=50k
F	rural_ps	|All=80k
F	motorway_ps	|All=110k,Goods=90k@>Weightrating:12t,Bus=100k@gSeats:12
F	living_street_pt	|All=20k
F	urban_pt	|All=50k,Hgv=40k@T
F	rural_pt	|All=90k;70k@T,Goods=80k;70k@T,Hgv=80k;70k@T,AutoRickshaw=80k,Bus=80k;70k@T
F	motorroad_pt	|All=100k;80k@T,Goods=90k;80k@T,Hgv=80k;70k@T,AutoRickshaw=90k,Bus=90k;90k@T
F	motorway_pt	All=50k|All=120k;100k@T,Goods=110k;90k@T,Hgv=90k;80k@T,AutoRickshaw=100k,Bus=100k;90k@T
F	urban_py	|All=50k,Motorcycle=40k,Hgv=40k,Bus=40k,Hazmat=40k
F	rural_py	|All=110k,Motorcycle=90k,Hgv=90k,Bus=90k,Hazmat=90k
F	living_street_ro	|All=20k
F	urban_ro	|All=50k,Hazmat=40k
F	rural_ro	|All=90k;80k@T,Hgv=80k;70k@T;70k@A;70k@>Weightrating:7.5t;60k@>Weightrating:7.5t&T;60k@>Weightrating:7.5t&A,Bus=80k;70k@T,Hazmat=70k
F	motorway_ro	All=50k|All=130k;120k@T,Hgv=110k;100k@T;100k@A;90k@>Weightrating:7.5t;80k@>Weightrating:7.5t&T;80k@>Weightrating:7.5t&A,Bus=110k;100k@T,Hazmat=70k
F	living_street_rs	|All=10k
F	urban_rs	|All=50k;80k@C,Hgv=80k;70k@>Weightrating:7.5t;70k@T,Bus=80k;70k@A,SchoolBus=70k
F	rural_rs	|All=80k;80k@C,Hgv=80k;70k@>Weightrating:7.5t;70k@T,Bus=80k;70k@A,SchoolBus=70k
F	motorroad_rs	|All=100k;80k@C,Hgv=80k;70k@>Weightrating:7.5t;70k@T,Bus=80k;70k@A,SchoolBus=70k
F	motorway_rs	All=50k|All=120k;80k@C,Hgv=100k;90k@>Weightrating:7.5t;90k@T,Bus=100k;90k@A,SchoolBus=90k
F	living_street_ru	|All=20k
F	urban_ru	|All=60k
F	rural_ru	|All=90k;70k@T,Coach=90k,Hgv=70k,Minibus=90k,Bus=70k,SchoolBus=60k,TruckBus=60k
F	motorway_ru	|All=110k;90k@T,Coach=90k,Hgv=90k,Minibus=90k,Bus=90k,SchoolBus=60k,TruckBus=60k
F	urban_rw	|All=40k
F	rural_rw	|All=80k,Goods=60k
F	urban_sa	|All=50k,Hgv=30k
F	rural_sa	|All=120k,Hgv=70k
F	urban_sd	|All=50k
F	living_street_se	|All=1w
F	urban_se	|All=50k,Coach=100k,Hgv=90k;80k@A,Bus=60k@A
F	rural_se	|All=70k,Coach=100k,Hgv=90k;80k@A,Bus=60k@A
F	motorway_se	All=40k|All=110k;80k@T,Coach=100k,Hgv=90k;80k@A,Bus=90k;60k@A
F	living_street_si	|All=10k
F	urban_si	|All=50k;80k@>Weightrating:3.5t;80k@C;70k@>Weightrating:3.5t&T,Hgv=80k;70k@T,Bus=80k;70k@>Weightrating:3.5t&T;70k@A,TruckBus=50k
F	rural_si	|All=90k;80k@>Weightrating:3.5t;80k@C;70k@>Weightrating:3.5t&T,Hgv=80k;70k@T,Bus=80k;70k@>Weightrating:3.5t&T;70k@A,TruckBus=50k
F	trunk_si	|All=110k;100k@T;80k@>Weightrating:3.5t;70k@>Weightrating:3.5t&T,Coach=100k,Hgv=90k;90k@>Weightrating:3.5t;80k@T;80k@>Weightrating:3.5t&T,Bus=80k;80k@A;80k@T,TruckBus=50k
F	motorway_si	All=60k|All=130k;100k@T;80k@>Weightrating:3.5t;70k@>Weightrating:3.5t&T,Coach=100k,Hgv=90k;90k@>Weightrating:3.5t;80k@T;80k@>Weightrating:3.5t&T,Bus=80k;80k@A;80k@T,TruckBus=50k
F	living_street_sk	|All=20k
F	urban_sk	|All=50k
F	rural_sk	|All=90k
F	motorroad_sk	All=80k|All=130k;90k@>TrailerWeight:0.75t,Hgv=90k,Bus=10090k@>TrailerWeight:0.75t
F	motorway_sk	All=80k|All=130k;90k@>TrailerWeight:0.75t,Hgv=90k,Bus=10090k@>TrailerWeight:0.75t
F	motorway_sn	|All=110k;85k@>TrailerWeight:0.75t,Motorcycle=100k,Hgv=85k;75k@>Weightrating:10t;65k@>Weightrating:16t;50k@>Weightrating:22t,Bus=90k;70k@gSeats:15
F	urban_ss	|All=45k
F	urban_sv	|All=50k,Hgv=40k,Bus=40k
F	rural_sv	|All=90k,Hgv=70k,Bus=70k
F	urban_td	|All=60k;40k@>Weightrating:3.5t
F	rural_td	|All=110k;90k@>Weightrating:3.5t;60k@>Weightrating:12.5t;60k@>TrailerWeight:0.75t,Bus=90k;60k@>Weightrating:12.5t;60k@>TrailerWeight:0.75t
F	urban_th	|All=80k;45k@T,Motorcycle=80k,Goods=60k@>Weight:2.2t,AutoRickshaw=45k,Minibus=80k,Bus=60k,SchoolBus=60k
F	rural_th	|All=90k;55k@T,Motorcycle=90k,Goods=80k@>Weight:2.2t,AutoRickshaw=55k,Minibus=90k,Bus=80k,SchoolBus=70k
F	urban_tl	|All=50k
F	rural_tl	|All=90k;70k@T,Goods=80k;70k@T,Hgv=80k;70k@T,Bus=80k;70k@T
F	motorroad_tl	|All=100k;80k@T,Goods=90k;80k@T,Hgv=80k;70k@T,Bus=90k;90k@T
F	motorway_tl	All=40k|All=120k;100k@T,Goods=110k;90k@T,Hgv=90k;80k@T,Bus=100k;90k@T
F	urban_tn	|All=50k,AutoRickshaw=50k
F	rural_tn	|All=90k;80k@>Weightrating:3.5t;70k@>Weightrating:12t;60k@>Weightrating:19t,AutoRickshaw=70k,Bus=90k;80k@>Weightrating:10t;70k@>Weightrating:12t;60k@>Weightrating:19t,Hazmat=70k@>Weightrating:3.5t;60k@>Weightrating:12t
F	motorway_tn	All=60k|All=110k;100k@>Weightrating:3.5t;90k@>Weightrating:12t;80k@>Weightrating:19t,AutoRickshaw=70k,Bus=110k;100k@>Weightrating:10t;90k@>Weightrating:12t;80k@>Weightrating:19t,Hazmat=90k@>Weightrating:3.5t;80k@>Weightrating:12t
F	urban_tr	|All=50k;40k@T,Hazmat=30k
F	rural_tr	All=15k|All=90k;80k@T,Motorcycle=80k;70k@T,Goods=80k;70k@T,Hgv=80k;70k@T,AutoRickshaw=70k;60k@T,Bus=80k;70k@T,Hazmat=50k
F	motorway_tr	All=40k|All=120k;110k@T,Motorcycle=100k;90k@T,Goods=110k;100k@T,Hgv=90k;0k@T,AutoRickshaw=80k;70k@T,Bus=100k;90k@T,Hazmat=70k
F	urban_tt	|All=50k
F	rural_tt	|All=80k;65k@T,Goods=65k,Bus=65k
F	urban_tz	|All=50k
F	rural_tz	|All=110k;80k@>Weightrating:3.5t
F	living_street_ua	|All=20k
F	urban_ua	|All=50k
F	rural_ua	|All=90k;80k@T,Motorcycle=80k,Bus=90k@gSeats:18,SchoolBus=80k,TruckBus=60k
F	motorway_ua	|All=130k;80k@T,Motorcycle=80k,Bus=90k@gSeats:18,SchoolBus=80k,TruckBus=60k
F	urban_ug	|All=50k;60k@T,Goods=60k,Bus=60k
F	rural_ug	|All=80k;60k@T,Goods=60k,Bus=60k
F	alley_us_ak	|All=15m
F	urban_us_ak	|All=25m
F	rural_us_ak	|All=55m;45m@C
F	urban_us_al	|All=30m,Hazmat=55m
F	rural_us_al	|All=45m,Hazmat=55m
F	urban_us_ar	|All=30m,Hgv=50m@>Weightcapacity:1.5s;30m@>Weightrating:64000p
F	rural_us_ar	|All=65m;55m@C,Hgv=50m@>Weightcapacity:1.5s;30m@>Weightrating:64000p
F	urban_us_az	|All=25m
F	rural_us_az	|All=65m
F	urban_us_ca	|All=25m
F	rural_us_ca	|All=55m;55m@T
F	urban_us_co	|All=30m
F	rural_us_co	|All=55m
F	motorway_us_co	|All=65m
F	motorway_us_ct	|All=65m,SchoolBus=50m
F	urban_us_de	|All=25m
F	rural_us_de	|All=50m
F	urban_us_fl	|All=30m
F	rural_us_fl	|All=55m
F	motorway_us_fl	|All=70m
F	urban_us_ga	|All=30m,SchoolBus=40m
F	rural_us_ga	|All=55m,SchoolBus=40m
F	rural_us_ia	|All=55m
F	motorway_us_ia	|All=65m
F	urban_us_id	|All=35m
F	rural_us_id	|All=55m
F	alley_us_il	|All=15m
F	urban_us_il	|All=30m
F	rural_us_il	|All=55m,Bus=55m
F	alley_us_in	|All=15m
F	urban_us_in	|All=30m;55m@>Length:85f,SchoolBus=40m
F	rural_us_in	|All=55m;55m@>Length:85f,SchoolBus=40m
F	urban_us_ks	|All=30m;55m@C
F	rural_us_ks	|All=55m;55m@C
F	urban_us_ky	|All=35m
F	rural_us_ky	|All=55m
F	motorway_us_la	|All=70m
F	urban_us_ma	|All=30m
F	rural_us_ma	|All=40m
F	urban_us_md	|All=30m
F	rural_us_md	|All=50m
F	urban_us_me	|All=25m,SchoolBus=45m
F	motorway_us_mi	All=55m|All=70m,Hgv=65m@>Weightrating:10000p;65m@T;65m@A,SchoolBus=65m
F	alley_us_mn	|All=10m
F	urban_us_mn	|All=30m
F	rural_us_mn	|All=55m
F	motorway_us_mn	|All=65m
F	rural_us_mo	|All=60m
F	urban_us_mt	|All=25m,Hgv=65m
F	rural_us_mt	|All=70m;65m@D6,Hgv=65m
F	urban_us_nc	|All=35m
F	rural_us_nc	|All=55m
F	urban_us_nd	|All=25m
F	rural_us_nd	|All=55m
F	urban_us_ne	|All=25m;50m@C
F	rural_us_ne	|All=55m;50m@C
F	motorway_us_ne	All=40m|All=70m;50m@C
F	urban_us_nh	|All=35m;45m@C
F	rural_us_nh	|All=55m;45m@C
F	urban_us_nj	|All=25m
F	rural_us_nj	|All=50m
F	urban_us_nm	|All=30m
F	rural_us_nm	|All=55m
F	alley_us_oh	|All=15m
F	urban_us_oh	|All=25m
F	rural_us_oh	|All=55m
F	rural_us_ok	|All=55m,SchoolBus=55m
F	alley_us_or	|All=15m
F	rural_us_or	|All=55m,Hgv=55m@>Weightrating:8000p&A;55m@>Weightrating:10000p,SchoolBus=55m,TruckBus=55m
F	urban_us_pa	|All=35m
F	rural_us_pa	|All=55m
F	urban_us_ri	|All=25m
F	rural_us_ri	|All=50m;45m@D7
F	urban_us_sc	|All=30m;45m@C
F	rural_us_sc	|All=55m;45m@C
F	urban_us_sd	|All=25m;45m@C
F	rural_us_sd	|All=65m;45m@C
F	rural_us_tn	|All=65m
F	alley_us_tx	|All=15m
F	urban_us_tx	|All=30m,SchoolBus=50m
F	rural_us_tx	|All=60m,SchoolBus=50m
F	urban_us_ut	|All=25m
F	rural_us_ut	|All=55m
F	urban_us_va	|All=35m,SchoolBus=45m
F	rural_us_va	|All=55m,SchoolBus=45m
F	motorway_us_va	|All=55m,SchoolBus=60m
F	urban_us_wa	|All=25m
F	rural_us_wa	|All=50m
F	alley_us_wi	|All=15m
F	urban_us_wi	|All=25m
F	rural_us_wi	|All=55m
F	motorway_us_wi	|All=70m
F	urban_us_wv	|All=25m
F	rural_us_wv	|All=55m
F	urban_us_wy	|All=30m
F	rural_us_wy	|All=65m
F	urban_uy	|All=45k
F	rural_uy	|All=90k;80k@T,Coach=90k,Hgv=80k,Bus=80k,Hazmat=80k
F	urban_uz	|All=70k
F	rural_uz	|All=100k;80k@T,Motorcycle=80k,Coach=90k,Goods=70k@T,Hgv=80k;70k@T,Minibus=90k,Bus=80k,SchoolBus=60k,TruckBus=60k
F	urban_ve	|All=40k
F	rural_ve	|All=70k;50k@D8
F	motorway_ve	|All=90k
F	urban_vi	|All=20m,Hgv=10m,Bus=10m
F	rural_vi	|All=35m,Hgv=30m,Bus=30m
F	motorway_vn	All=50k|All=120k
F	urban_ws	|All=25m
F	rural_ws	|All=35m
F	urban_xk	|All=50k;80k@C,Goods=80k;70k@T;70k@>Weightrating:7.5t,Bus=80k,SchoolBus=70k,Hazmat=70k
F	rural_xk	|All=80k;80k@C,Goods=80k;70k@T;70k@>Weightrating:7.5t,Bus=80k,SchoolBus=70k,Hazmat=70k
F	motorroad_xk	|All=110k;80k@C,Goods=85k;80k@T;70k@>Weightrating:12t,Bus=100k;80k@>Weightrating:12t,SchoolBus=70k,Hazmat=70k
F	motorway_xk	All=60k|All=130k;80k@C,Goods=85k;80k@T;70k@>Weightrating:12t,Bus=100k;80k@>Weightrating:12t,SchoolBus=70k,Hazmat=70k
F	urban_za	|All=60k,Hgv=80k@>Weightrating:9t,Bus=100k
F	rural_za	|All=100k,Hgv=80k@>Weightrating:9t,Bus=100k
F	motorway_za	|All=120k,Hgv=80k@>Weightrating:9t,Bus=100k
F	urban_zm	|All=40k
F	rural_zm	|All=100k,Hgv=80k
D	alley	US-AK	alley_us_ak
D	alley	US-IL	alley_us_il
D	alley	US-IN	alley_us_in
D	alley	US-MN	alley_us_mn
D	alley	US-OH	alley_us_oh
D	alley	US-OR	alley_us_or
D	alley	US-TX	alley_us_tx
D	alley	US-WI	alley_us_wi
D	living_street	AD	living_street_ad
D	living_street	AM	living_street_am
D	living_street	AT	living_street_at
D	living_street	AZ	living_street_az
D	living_street	BA	living_street_ba
D	living_street	BE-BRU	living_street_be_bru
D	living_street	BE-VLG	living_street_be_vlg
D	living_street	BE-WAL	living_street_be_wal
D	living_street	BG	living_street_bg
D	living_street	BW	living_street_bw
D	living_street	BY	living_street_by
D	living_street	CH	living_street_ch
D	living_street	CZ	living_street_cz
D	living_street	DE	living_street_de
D	living_street	DK	living_street_dk
D	living_street	EE	living_street_ee
D	living_street	ES	living_street_es
D	living_street	FI	living_street_fi
D	living_street	FR	living_street_fr
D	living_street	GE	living_street_ge
D	living_street	HR	living_street_hr
D	living_street	HU	living_street_hu
D	living_street	IL	living_street_il
D	living_street	IM	living_street_im
D	living_street	IS	living_street_is
D	living_street	KZ	living_street_kz
D	living_street	LT	living_street_lt
D	living_street	LU	living_street_lu
D	living_street	LV	living_street_lv
D	living_street	MD	living_street_md
D	living_street	MN	living_street_mn
D	living_street	MX	living_street_mx
D	living_street	NL	living_street_nl
D	living_street	NO	living_street_no
D	living_street	NZ	living_street_nz
D	living_street	PL	living_street_pl
D	living_street	PT	living_street_pt
D	living_street	RO	living_street_ro
D	living_street	RS	living_street_rs
D	living_street	RU	living_street_ru
D	living_street	SE	living_street_se
D	living_street	SI	living_street_si
D	living_street	SK	living_street_sk
D	living_street	UA	living_street_ua
D	motorroad	AD	motorroad_ad
D	motorroad	AO	motorroad_ao
D	motorroad	AT	motorroad_at
D	motorroad	BA	motorroad_ba
D	motorroad	BG	motorroad_bg
D	motorroad	CH	motorroad_ch
D	motorroad	CV	motorroad_cv
D	motorroad	CW	motorroad_cw
D	motorroad	DK	motorroad_dk
D	motorroad	GR	motorroad_gr
D	motorroad	HR	motorroad_hr
D	motorroad	HU	motorroad_hu
D	motorroad	KR	motorroad_kr
D	motorroad	LT	motorroad_lt
D	motorroad	LV	motorroad_lv
D	motorroad	MD	motorroad_md
D	motorroad	MK	motorroad_mk
D	motorroad	PT	motorroad_pt
D	motorroad	RS	motorroad_rs
D	motorroad	SK	motorroad_sk
D	motorroad	TL	motorroad_tl
D	motorroad	XK	motorroad_xk
D	motorway	AD	motorway_ad
D	motorway	AE	motorway_ae
D	motorway	AL	motorway_al
D	motorway	AM	motorway_am
D	motorway	AO	motorway_ao
D	motorway	AR	motorway_ar
D	motorway	AT	motorway_at
D	motorway	AZ	motorway_az
D	motorway	BA	motorway_ba
D	motorway	BE-BRU	motorway_be_bru
D	motorway	BE-VLG	motorway_be_vlg
D	motorway	BE-WAL	motorway_be_wal
D	motorway	BG	motorway_bg
D	motorway	BJ	motorway_bj
D	motorway	BY	motorway_by
D	motorway	CD	motorway_cd
D	motorway	CH	motorway_ch
D	motorway	CI	motorway_ci
D	motorway	CN	motorway_cn
D	motorway	CO	motorway_co
D	motorway	CU	motorway_cu
D	motorway	CV	motorway_cv
D	motorway	DE	motorway_de
D	motorway	DK	motorway_dk
D	motorway	ES	motorway_es
D	motorway	FR	motorway_fr
D	motorway	GB	motorway_gb
D	motorway	GB-SCT	motorway_gb_sct
D	motorway	GE	motorway_ge
D	motorway	GH	motorway_gh
D	motorway	GR	motorway_gr
D	motorway	HR	motorway_hr
D	motorway	HU	motorway_hu
D	motorway	IE	motorway_ie
D	motorway	IL	motorway_il
D	motorway	IN	motorway_in
D	motorway	IT	motorway_it
D	motorway	JP	motorway_jp
D	motorway	KG	motorway_kg
D	motorway	KR	motorway_kr
D	motorway	KZ	motorway_kz
D	motorway	LS	motorway_ls
D	motorway	LT	motorway_lt
D	motorway	LU	motorway_lu
D	motorway	MK	motorway_mk
D	motorway	NA	motorway_na
D	motorway	NE	motorway_ne
D	motorway	NG	motorway_ng
D	motorway	NO	motorway_no
D	motorway	PA	motorway_pa
D	motorway	PL	motorway_pl
D	motorway	PR	motorway_pr
D	motorway	PS	motorway_ps
D	motorway	PT	motorway_pt
D	motorway	RO	motorway_ro
D	motorway	RS	motorway_rs
D	motorway	RU	motorway_ru
D	motorway	SE	motorway_se
D	motorway	SI	motorway_si
D	motorway	SK	motorway_sk
D	motorway	SN	motorway_sn
D	motorway	TL	motorway_tl
D	motorway	TN	motorway_tn
D	motorway	TR	motorway_tr
D	motorway	UA	motorway_ua
D	motorway	US-CO	motorway_us_co
D	motorway	US-CT	motorway_us_ct
D	motorway	US-FL	motorway_us_fl
D	motorway	US-IA	motorway_us_ia
D	motorway	US-LA	motorway_us_la
D	motorway	US-MI	motorway_us_mi
D	motorway	US-MN	motorway_us_mn
D	motorway	US-NE	motorway_us_ne
D	motorway	US-VA	motorway_us_va
D	motorway	US-WI	motorway_us_wi
D	motorway	VE	motorway_ve
D	motorway	VN	motorway_vn
D	motorway	XK	motorway_xk
D	motorway	ZA	motorway_za
D	nsl_dual	GB	nsl_dual_gb
D	nsl_dual	GB-SCT	nsl_dual_gb_sct
D	nsl_restricted	GB	nsl_restricted_gb
D	nsl_restricted	GB-SCT	nsl_restricted_gb_sct
D	nsl_single	GB	nsl_single_gb
D	nsl_single	GB-SCT	nsl_single_gb_sct
D	pedestrian	MX	pedestrian_mx
D	rural	AE	rural_ae
D	rural	AG	rural_ag
D	rural	AL	rural_al
D	rural	AM	rural_am
D	rural	AO	rural_ao
D	rural	AR	rural_ar
D	rural	AS	rural_as
D	rural	AT	rural_at
D	rural	AU	rural_au
D	rural	AU-ACT	rural_au_act
D	rural	AU-NSW	rural_au_nsw
D	rural	AU-NT	rural_au_nt
D	rural	AU-QLD	rural_au_qld
D	rural	AU-SA	rural_au_sa
D	rural	AU-VIC	rural_au_vic
D	rural	AU-WA	rural_au_wa
D	rural	AW	rural_aw
D	rural	AZ	rural_az
D	rural	BA	rural_ba
D	rural	BE-BRU	rural_be_bru
D	rural	BE-VLG	rural_be_vlg
D	rural	BE-WAL	rural_be_wal
D	rural	BF	rural_bf
D	rural	BG	rural_bg
D	rural	BH	rural_bh
D	rural	BI	rural_bi
D	rural	BN	rural_bn
D	rural	BS	rural_bs
D	rural	BS-NP	rural_bs_np
D	rural	BT	rural_bt
D	rural	BW	rural_bw
D	rural	BY	rural_by
D	rural	CA-AB	rural_ca_ab
D	rural	CA-BC	rural_ca_bc
D	rural	CA-MB	rural_ca_mb
D	rural	CA-NB	rural_ca_nb
D	rural	CA-NL	rural_ca_nl
D	rural	CA-NS	rural_ca_ns
D	rural	CA-NT	rural_ca_nt
D	rural	CA-NU	rural_ca_nu
D	rural	CA-ON	rural_ca_on
D	rural	CA-PE	rural_ca_pe
D	rural	CA-QC	rural_ca_qc
D	rural	CD	rural_cd
D	rural	CF	rural_cf
D	rural	CG	rural_cg
D	rural	CH	rural_ch
D	rural	CI	rural_ci
D	rural	CL	rural_cl
D	rural	CM	rural_cm
D	rural	CO	rural_co
D	rural	CR	rural_cr
D	rural	CU	rural_cu
D	rural	CV	rural_cv
D	rural	CW	rural_cw
D	rural	CZ	rural_cz
D	rural	DE	rural_de
D	rural	DK	rural_dk
D	rural	DO	rural_do
D	rural	EC	rural_ec
D	rural	EE	rural_ee
D	rural	ES	rural_es
D	rural	FI	rural_fi
D	rural	FJ	rural_fj
D	rural	FM-KSA	rural_fm_ksa
D	rural	FM-TRK	rural_fm_trk
D	rural	FM-YAP	rural_fm_yap
D	rural	FR	rural_fr
D	rural	GA	rural_ga
D	rural	GD	rural_gd
D	rural	GE	rural_ge
D	rural	GH	rural_gh
D	rural	GQ	rural_gq
D	rural	GR	rural_gr
D	rural	GY	rural_gy
D	rural	HR	rural_hr
D	rural	HU	rural_hu
D	rural	IE	rural_ie
D	rural	IL	rural_il
D	rural	IM	rural_im
D	rural	IN	rural_in
D	rural	IS	rural_is
D	rural	IT	rural_it
D	rural	KE	rural_ke
D	rural	KG	rural_kg
D	rural	KH	rural_kh
D	rural	KI	rural_ki
D	rural	KN	rural_kn
D	rural	KR	rural_kr
D	rural	KZ	rural_kz
D	rural	LI	rural_li
D	rural	LR	rural_lr
D	rural	LS	rural_ls
D	rural	LT	rural_lt
D	rural	LU	rural_lu
D	rural	LV	rural_lv
D	rural	MD	rural_md
D	rural	MH	rural_mh
D	rural	MK	rural_mk
D	rural	MM	rural_mm
D	rural	MN	rural_mn
D	rural	MS	rural_ms
D	rural	MT	rural_mt
D	rural	MW	rural_mw
D	rural	MX	rural_mx
D	rural	MZ	rural_mz
D	rural	NA	rural_na
D	rural	NG	rural_ng
D	rural	NI	rural_ni
D	rural	NL	rural_nl
D	rural	NL-BQ1	rural_nl_bq1
D	rural	NL-BQ2	rural_nl_bq2
D	rural	NL-BQ3	rural_nl_bq3
D	rural	NO	rural_no
D	rural	NP	rural_np
D	rural	NZ	rural_nz
D	rural	PA	rural_pa
D	rural	PE	rural_pe
D	rural	PG	rural_pg
D	rural	PK	rural_pk
D	rural	PL	rural_pl
D	rural	PR	rural_pr
D	rural	PS	rural_ps
D	rural	PT	rural_pt
D	rural	PY	rural_py
D	rural	RO	rural_ro
D	rural	RS	rural_rs
D	rural	RU	rural_ru
D	rural	RW	rural_rw
D	rural	SA	rural_sa
D	rural	SE	rural_se
D	rural	SI	rural_si
D	rural	SK	rural_sk
D	rural	SV	rural_sv
D	rural	TD	rural_td
D	rural	TH	rural_th
D	rural	TL	rural_tl
D	rural	TN	rural_tn
D	rural	TR	rural_tr
D	rural	TT	rural_tt
D	rural	TZ	rural_tz
D	rural	UA	rural_ua
D	rural	UG	rural_ug
D	rural	US-AK	rural_us_ak
D	rural	US-AL	rural_us_al
D	rural	US-AR	rural_us_ar
D	rural	US-AZ	rural_us_az
D	rural	US-CA	rural_us_ca
D	rural	US-CO	rural_us_co
D	rural	US-DE	rural_us_de
D	rural	US-FL	rural_us_fl
D	rural	US-GA	rural_us_ga
D	rural	US-IA	rural_us_ia
D	rural	US-ID	rural_us_id
D	rural	US-IL	rural_us_il
D	rural	US-IN	rural_us_in
D	rural	US-KS	rural_us_ks
D	rural	US-KY	rural_us_ky
D	rural	US-MA	rural_us_ma
D	rural	US-MD	rural_us_md
D	rural	US-MN	rural_us_mn
D	rural	US-MO	rural_us_mo
D	rural	US-MT	rural_us_mt
D	rural	US-NC	rural_us_nc
D	rural	US-ND	rural_us_nd
D	rural	US-NE	rural_us_ne
D	rural	US-NH	rural_us_nh
D	rural	US-NJ	rural_us_nj
D	rural	US-NM	rural_us_nm
D	rural	US-OH	rural_us_oh
D	rural	US-OK	rural_us_ok
D	rural	US-OR	rural_us_or
D	rural	US-PA	rural_us_pa
D	rural	US-RI	rural_us_ri
D	rural	US-SC	rural_us_sc
D	rural	US-SD	rural_us_sd
D	rural	US-TN	rural_us_tn
D	rural	US-TX	rural_us_tx
D	rural	US-UT	rural_us_ut
D	rural	US-VA	rural_us_va
D	rural	US-WA	rural_us_wa
D	rural	US-WI	rural_us_wi
D	rural	US-WV	rural_us_wv
D	rural	US-WY	rural_us_wy
D	rural	UY	rural_uy
D	rural	UZ	rural_uz
D	rural	VE	rural_ve
D	rural	VI	rural_vi
D	rural	WS	rural_ws
D	rural	XK	rural_xk
D	rural	ZA	rural_za
D	rural	ZM	rural_zm
D	service	AE	service_ae
D	service	AZ	service_az
D	service	CU	service_cu
D	service	MX	service_mx
D	trunk	SI	trunk_si
D	urban	AD	urban_ad
D	urban	AG	urban_ag
D	urban	AL	urban_al
D	urban	AM	urban_am
D	urban	AO	urban_ao
D	urban	AS	urban_as
D	urban	AT	urban_at
D	urban	AU	urban_au
D	urban	AU-ACT	urban_au_act
D	urban	AU-NSW	urban_au_nsw
D	urban	AU-NT	urban_au_nt
D	urban	AU-QLD	urban_au_qld
D	urban	AU-SA	urban_au_sa
D	urban	AU-TAS	urban_au_tas
D	urban	AU-VIC	urban_au_vic
D	urban	AU-WA	urban_au_wa
D	urban	AW	urban_aw
D	urban	AZ	urban_az
D	urban	BA	urban_ba
D	urban	BE-BRU	urban_be_bru
D	urban	BE-VLG	urban_be_vlg
D	urban	BE-WAL	urban_be_wal
D	urban	BF	urban_bf
D	urban	BG	urban_bg
D	urban	BH	urban_bh
D	urban	BI	urban_bi
D	urban	BJ	urban_bj
D	urban	BN	urban_bn
D	urban	BO	urban_bo
D	urban	BS	urban_bs
D	urban	BS-NP	urban_bs_np
D	urban	BT	urban_bt
D	urban	BW	urban_bw
D	urban	BY	urban_by
D	urban	CA-BC	urban_ca_bc
D	urban	CA-MB	urban_ca_mb
D	urban	CA-NB	urban_ca_nb
D	urban	CA-NL	urban_ca_nl
D	urban	CA-NT	urban_ca_nt
D	urban	CA-NU	urban_ca_nu
D	urban	CA-ON	urban_ca_on
D	urban	CA-PE	urban_ca_pe
D	urban	CA-QC	urban_ca_qc
D	urban	CD	urban_cd
D	urban	CF	urban_cf
D	urban	CG	urban_cg
D	urban	CH	urban_ch
D	urban	CI	urban_ci
D	urban	CL	urban_cl
D	urban	CM	urban_cm
D	urban	CN	urban_cn
D	urban	CO	urban_co
D	urban	CR	urban_cr
D	urban	CU	urban_cu
D	urban	CV	urban_cv
D	urban	CW	urban_cw
D	urban	CY	urban_cy
D	urban	CZ	urban_cz
D	urban	DE	urban_de
D	urban	DK	urban_dk
D	urban	DO	urban_do
D	urban	EC	urban_ec
D	urban	EE	urban_ee
D	urban	EG	urban_eg
D	urban	ES	urban_es
D	urban	FI	urban_fi
D	urban	FJ	urban_fj
D	urban	FM-KSA	urban_fm_ksa
D	urban	FM-TRK	urban_fm_trk
D	urban	FM-YAP	urban_fm_yap
D	urban	FR	urban_fr
D	urban	GA	urban_ga
D	urban	GD	urban_gd
D	urban	GE	urban_ge
D	urban	GH	urban_gh
D	urban	GQ	urban_gq
D	urban	GR	urban_gr
D	urban	GY	urban_gy
D	urban	HR	urban_hr
D	urban	HT	urban_ht
D	urban	HU	urban_hu
D	urban	ID	urban_id
D	urban	IE	urban_ie
D	urban	IL	urban_il
D	urban	IM	urban_im
D	urban	IN	urban_in
D	urban	IS	urban_is
D	urban	IT	urban_it
D	urban	KE	urban_ke
D	urban	KG	urban_kg
D	urban	KH	urban_kh
D	urban	KI	urban_ki
D	urban	KN	urban_kn
D	urban	KR	urban_kr
D	urban	KZ	urban_kz
D	urban	LI	urban_li
D	urban	LR	urban_lr
D	urban	LS	urban_ls
D	urban	LT	urban_lt
D	urban	LU	urban_lu
D	urban	LV	urban_lv
D	urban	MD	urban_md
D	urban	MH	urban_mh
D	urban	MK	urban_mk
D	urban	MM	urban_mm
D	urban	MN	urban_mn
D	urban	MS	urban_ms
D	urban	MT	urban_mt
D	urban	MW	urban_mw
D	urban	MX	urban_mx
D	urban	MZ	urban_mz
D	urban	NA	urban_na
D	urban	NE	urban_ne
D	urban	NG	urban_ng
D	urban	NI	urban_ni
D	urban	NL	urban_nl
D	urban	NL-BQ1	urban_nl_bq1
D	urban	NL-BQ2	urban_nl_bq2
D	urban	NL-BQ3	urban_nl_bq3
D	urban	NO	urban_no
D	urban	NP	urban_np
D	urban	NZ	urban_nz
D	urban	PA	urban_pa
D	urban	PE	urban_pe
D	urban	PG	urban_pg
D	urban	PH	urban_ph
D	urban	PK	urban_pk
D	urban	PL	urban_pl
D	urban	PR	urban_pr
D	urban	PS	urban_ps
D	urban	PT	urban_pt
D	urban	PY	urban_py
D	urban	RO	urban_ro
D	urban	RS	urban_rs
D	urban	RU	urban_ru
D	urban	RW	urban_rw
D	urban	SA	urban_sa
D	urban	SD	urban_sd
D	urban	SE	urban_se
D	urban	SI	urban_si
D	urban	SK	urban_sk
D	urban	SS	urban_ss
D	urban	SV	urban_sv
D	urban	TD	urban_td
D	urban	TH	urban_th
D	urban	TL	urban_tl
D	urban	TN	urban_tn
D	urban	TR	urban_tr
D	urban	TT	urban_tt
D	urban	TZ	urban_tz
D	urban	UA	urban_ua
D	urban	UG	urban_ug
D	urban	US-AK	urban_us_ak
D	urban	US-AL	urban_us_al
D	urban	US-AR	urban_us_ar
D	urban	US-AZ	urban_us_az
D	urban	US-CA	urban_us_ca
D	urban	US-CO	urban_us_co
D	urban	US-DE	urban_us_de
D	urban	US-FL	urban_us_fl
D	urban	US-GA	urban_us_ga
D	urban	US-ID	urban_us_id
D	urban	US-IL	urban_us_il
D	urban	US-IN	urban_us_in
D	urban	US-KS	urban_us_ks
D	urban	US-KY	urban_us_ky
D	urban	US-MA	urban_us_ma
D	urban	US-MD	urban_us_md
D	urban	US-ME	urban_us_me
D	urban	US-MN	urban_us_mn
D	urban	US-MT	urban_us_mt
D	urban	US-NC	urban_us_nc
D	urban	US-ND	urban_us_nd
D	urban	US-NE	urban_us_ne
D	urban	US-NH	urban_us_nh
D	urban	US-NJ	urban_us_nj
D	urban	US-NM	urban_us_nm
D	urban	US-OH	urban_us_oh
D	urban	US-PA	urban_us_pa
D	urban	US-RI	urban_us_ri
D	urban	US-SC	urban_us_sc
D	urban	US-SD	urban_us_sd
D	urban	US-TX	urban_us_tx
D	urban	US-UT	urban_us_ut
D	urban	US-VA	urban_us_va
D	urban	US-WA	urban_us_wa
D	urban	US-WI	urban_us_wi
D	urban	US-WV	urban_us_wv
D	urban	US-WY	urban_us_wy
D	urban	UY	urban_uy
D	urban	UZ	urban_uz
D	urban	VE	urban_ve
D	urban	VI	urban_vi
D	urban	WS	urban_ws
D	urban	XK	urban_xk
D	urban	ZA	urban_za
D	urban	ZM	urban_zm
C	alley	alley
C	living_street	living_street
C	motorroad	motorroad
C	motorway	motorway
C	nsl_dual	nsl_dual
C	nsl_restricted	nsl_restricted
C	nsl_single	nsl_single
C	pedestrian	pedestrian
C	rural	rural
C	service	service
C	trunk	trunk
C	urban	urban
"""#
}
