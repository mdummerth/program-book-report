USE [impresario]
GO
/****** Object:  StoredProcedure [dbo].[LRP_PROGRAM_BOOK]    Script Date: 7/24/2018 2:01:17 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO


ALTER PROCEDURE [dbo].[LRP_PROGRAM_BOOK]
	(
		@program varchar(4000) = 1, --select program_no, name from t_program
		@mode int, --review = 1, history/data load = 2
		@start_dt datetime
		)
AS
/*
CREATED: 10/13/2015
By: Jasmine Hirst
Purpose: Custom Program Book Report

EDITED: 7/20/2018
By: Madeline Dummerth
Purpose: Use case edits

grant exec on LRP_PROGRAM_BOOK to impusers

select * from t_program
Manual listing Attributue value = 425

84	1	Review Only
84	2	Update

exec LRP_PROGRAM_BOOK
@program = '6', 
@mode = 1,
@start_dt = '6/27/2017'

select * from t_program

declare @program varchar(4000)= '5,6,7,8,9,10' 
select Element from FT_SPLIT_LIST(@program, ',')

--debug--
drop table #base
drop table #gift_sum
drop table #export
drop table #program
drop table #memb


declare 
		@program varchar(4000),
		@mode int, --review = 1, history/data load = 2
		@start_dt datetime

set @program = '7,9'
set @mode = 1
set @start_dt = '11-01-2015'

----test
select * from tx_cust_program where customer_no = 205168
delete from tx_cust_program where customer_no = 132592 and program_no = 6
select * from #export where customer_no = 205168
select * from #base where customer_no = 205168
*/		


if @start_dt is null set @start_dt = '01-01-1900'


--get all active memberships
select customer_no, memb_level 
into #memb
from  TX_CUST_MEMBERSHIP cm 
where current_status = 2 --active



--get all giving to appropriate campaigns within timeframe 
select a.ref_no, a.cont_dt, a.customer_no, a.cont_amt, cm.memb_level, ml.donation_id, --p.pmt_method,
 cr.creditee_type
into #base
from T_CONTRIBUTION a
left join TX_CUST_MEMBERSHIP cm on a.customer_no = cm.customer_no and current_status = 2 --active
left join ltr_program_memb_level ml on cm.memb_level = ml.memb_level
join T_CAMPAIGN b on a.campaign_no = b.campaign_no
left join T_CUSTOMER c on a.customer_no = c.customer_no
left join T_TRANSACTION t on a.ref_no = t.ref_no
left join T_PAYMENT p on t.transaction_no = p.transaction_no
left join T_CREDITEE cr on a.ref_no = cr.ref_no
where a.cont_amt > 0
and a.cont_dt >= @start_dt
and a.fund_no not in (4,5,3,6,27,33,71)
group by a.ref_no, a.cont_dt, a.customer_no, a.cont_amt, cm.memb_level, ml.donation_id, --p.pmt_method, 
cr.creditee_type


--get all open pledges
insert #base
select a.ref_no, a.cont_dt, a.customer_no, a.cont_amt, cm.memb_level, ml.donation_id, --p.pmt_method, 
cr.creditee_type
from T_CONTRIBUTION a
left join TX_CUST_MEMBERSHIP cm on a.customer_no = cm.customer_no and current_status = 2 --active
left join ltr_program_memb_level ml on cm.memb_level = ml.memb_level
join T_CAMPAIGN b on a.campaign_no = b.campaign_no
join T_CUSTOMER c on a.customer_no = c.customer_no
join T_TRANSACTION t on a.ref_no = t.ref_no
join T_PAYMENT p on t.transaction_no = p.transaction_no
join T_CREDITEE cr on a.ref_no = cr.ref_no
where a.cont_amt > 0
and a.cont_type = 'P'
and a.recd_amt < a.cont_amt
and a.fund_no not in (4,5,3,6,27,33,71)
--and b.control_group in (1,3)
and a.ref_no not in (select ref_no from #base)
group by a.ref_no, a.cont_dt, a.customer_no, a.cont_amt, cm.memb_level, ml.donation_id, --p.pmt_method, 
cr.creditee_type

-- select * from #base where customer_no = 193889 --md testing

--get all government listing
update data
set data.donation_id = 17 
from #base data
join T_CUSTOMER c on data.customer_no = c.customer_no
where c.cust_type = 5 --Government Agency

--get all in-kind
--update #base
--set donation_id = 18 
--where pmt_method = 22

--get matching commented out to allow for proper name levels
--update #base
--set donation_id = 19
--where creditee_type = 1

--soft credits
update #base
set customer_no = a.creditee_no
from T_CREDITEE a
where a.ref_no = #base.ref_no and #base.creditee_type in (11,7,5,1,10,12,4) --added creditee type definition

-- assigns correction memb_level and donation_id to creditee rows
update #base
set memb_level = cm.memb_level
FROM TX_CUST_MEMBERSHIP cm
WHERE cm.customer_no = #base.customer_no and current_status = 2 and #base.creditee_type in (11,7,5,1,10,12,4)

update #base
set donation_id = ml.donation_id
FROM ltr_program_memb_level ml
WHERE ml.memb_level = #base.memb_level and #base.creditee_type in (11,7,5,1,10,12,4)

--remove records with no donation_id
delete #base 
where donation_id is null

--sum up
create table #gift_sum
(customer_no int null,
donation_id int null,
memb_level varchar(10) null,
total_cont money null
)


insert #gift_sum
select a.customer_no, a.donation_id,a.memb_level, total_cont = SUM(a.cont_amt)
from #base a
join T_CUSTOMER b on a.customer_no = b.customer_no
where a.cont_amt > 0
group by a.customer_no, a.donation_id, a.memb_level


--program
select program_no, name
into #program
from T_PROGRAM
where program_no in (select Element from FT_SPLIT_LIST(@program, ','))
--and program_no <> 1 --default



--get donation
create table #export
(	customer_no int null,
	memb_level varchar(20) null,
	total_cont money null,
	program_no int null,
	donation_id int null,
	level_description varchar(60) null,
	list_name varchar(250) null,
	sort_Name varchar(250) null,
	manual_listing varchar(5) null,
	constituencies varchar(250) null,
	prev_level varchar(60) null,
	movement varchar(30) null,
	deceased varchar(5) null,
	last_gift_dt datetime null,
	last_gift_amt money null
	)
	
insert #export
select distinct
	a.customer_no, b.memb_level, isnull(a.total_cont, 0)total_cont, b.program_no, b.donation_id ,b.level_name,
	list_name = isnull(c.cust_pname,d.esal1_desc),
	sort_name = ISNULL(c.sort_name, e.sort_name),
	manual_listing = case when f.key_value = 'Yes' then 'Yes' else '' end,
	constituencies = dbo.FS_CONST_STRING_NEW(a.customer_no, 'Y'),
	prev_level =  case when ml.end_amt < 50000 then replace(ml.description, 'corp ', '')+' $'+ replace(convert(varchar, ml.start_amt ,1) ,'.00','')+'-$'+replace(convert(varchar, ml.end_amt ,1) ,'.99','')
				  else replace(replace(ml.description, 'corp associate ', ''), 'corp lead ', '')+' $'+ replace(convert(varchar, ml.start_amt ,1) ,'.00','')+'+'
				  end,
	movement = 
	  case when ISNULL(a.memb_level,'') = ISNULL(b.memb_level,'') then 'Same'
		when ISNULL(a.memb_level, '') = '' then 'New'
		else 'Change' end,
	deceased = case when e.name_status = 2 and e.cust_type = 1 then 'N1  ' else null end,
	last_gift_dt = null,
	last_gift_amt = null
from #gift_sum a
left join ltr_program_memb_level b on a.total_cont between b.start_amt and b.end_amt and substring(a.memb_level,1,2) = substring(b.memb_level,1,2)
--left join #program p on b.program_no = p.program_no
left join T_MEMB_LEVEL ml on a.memb_level = ml.memb_level
left join (select customer_no, cust_pname, sort_name, ROW_NUMBER() over (PARTITION by customer_no order by (select null))row# from TX_CUST_PROGRAM)c on a.customer_no = c.customer_no  and c.row# = 1
left outer join tx_cust_sal d on a.customer_no = d.customer_no and d.default_ind = 'Y'
left outer join FT_CONSTITUENT_DISPLAY_NAME() fn on a.customer_no = fn.customer_no
left outer join T_CUSTOMER e on a.customer_no = e.customer_no
left outer join TX_CUST_KEYWORD f on a.customer_no = f.customer_no and f.keyword_no = 425	--CSA Manual Program Listing 
		and f.key_value = 'Yes' 	--manual listing

--update program 8,9,10
update data
set program_no = 8,
level_description = 'Public Support'
from #export data
join T_CUSTOMER c on data.customer_no = c.customer_no
where c.cust_type = 5
and donation_id = 17

update #export
set program_no = 9,
level_description = 'In-Kind Support'
where donation_id = 18

update #export
set program_no = 10,
level_description = 'Matching Companies'
where donation_id = 19


--manual update
update #export
set list_name = a.cust_pname, 
sort_Name = a.sort_name,
donation_id = a.donation_level, level_description = b.description, movement = 'Manual'
from TX_CUST_PROGRAM a
join TR_DONATION_LEVEL b on a.donation_level = b.id and a.program_no = b.program_no
left join FT_CONSTITUENT_DISPLAY_NAME() fn on a.customer_no = fn.customer_no
where a.customer_no = #export.customer_no
and a.program_no in (select program_no from #program)
and #export.manual_listing = 'Yes'


--manual add
insert #export
select
	a.customer_no, d.cust_type, 0, b.program_no, b.donation_level, c.description,
	b.cust_pname, b.sort_name, 'Yes', constituencies = dbo.FS_CONST_STRING_NEW(a.customer_no, 'Y'),
	null, 'Manual', null, null, null
from tx_cust_keyword a
join tx_cust_program b on a.customer_no = b.customer_no
join tr_donation_level c on b.donation_level = c.id
join t_customer d on a.customer_no = d.customer_no
where a.keyword_no = 425
and b.program_no in (select program_no from #program)
and a.customer_no not in (select customer_no from #export)
and a.key_value like 'Yes'



--last gift info
update #export
set last_gift_amt = (select top 1 cont_amt from T_CONTRIBUTION a 
						join T_CAMPAIGN b on a.campaign_no = b.campaign_no
						where a.customer_no = #export.customer_no and a.cont_amt > 0
						--and b.control_group in (1,3) 
							order by a.cont_dt desc),
last_gift_dt =  (select top 1 cont_dt from T_CONTRIBUTION a 
				join T_CAMPAIGN b on a.campaign_no = b.campaign_no
						where a.customer_no = #export.customer_no and a.cont_amt > 0 
						--and b.control_group in (1,3)
							order by a.cont_dt desc)


--deceased update
update #export
set deceased = 'N1'
from T_AFFILIATION a
where a.group_customer_no = #export.customer_no
and a.name_ind = -1
and a.individual_customer_no in (select customer_no from T_CUSTOMER where name_status = 2)


update #export 
set deceased = 'Both'
from T_AFFILIATION a
where a.group_customer_no = #export.customer_no
and a.name_ind = -2
and a.individual_customer_no in (select customer_no from T_CUSTOMER where name_status = 2)
and #export.deceased = 'N1'

update #export
set deceased = 'N2'
from T_AFFILIATION a
where a.group_customer_no = #export.customer_no
and a.name_ind = -2
and a.individual_customer_no in (select customer_no from T_CUSTOMER where name_status = 2)
and #export.deceased is null

--clean up
delete #export where level_description is null

--export data
select distinct customer_no, memb_level,total_cont,program_no,donation_id, level_description, list_name, sort_Name, manual_listing,constituencies,prev_level,movement,deceased,last_gift_dt,last_gift_amt  from #export
where program_no in (select distinct program_no from #program) 

--populate tx_cust_program
if @mode = 2
begin
		update TX_CUST_PROGRAM 
		set donation_level = a.donation_id
		from #export a
		where (1=1)
		and a.customer_no not in (select customer_no from TX_CUST_KEYWORD where keyword_no = 425)
		and tx_cust_program.customer_no = a.customer_no
		and donation_level <> a.donation_id
		and donation_level not in (17,18,19)
		
		insert TX_CUST_PROGRAM(customer_no, program_no, donation_level, cust_pname, sort_name)
		select
			a.customer_no, a.program_no, a.donation_id, left(a.list_name,70), LEFT(a.sort_name,30)
		from #export a
		where (1=1)
		and a.customer_no not in (select customer_no from TX_CUST_KEYWORD where keyword_no = 425)
		and not exists (select * from TX_CUST_PROGRAM b where b.customer_no = a.customer_no and b.program_no = a.program_no)
		group by a.customer_no, a.program_no, a.donation_id, left(a.list_name,70), LEFT(a.sort_name,30)
		
		
end
