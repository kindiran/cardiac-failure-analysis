--Q1. Update the demography table. Add a random age  for each patient that falls within their respective age category. Update the newly added age to be an integer.

--step 1: Create a user-defined procedure to add a new column to the existing table. We will also use this procedure for the other questions.
create or replace procedure pr_add_new_column_to_table
(tablename varchar, columnname varchar, columntype varchar) 
language plpgsql
as
$$
begin
   -- Check if column already exists
   if not exists (
      select 1 
      from information_schema.columns 
      where table_name = tablename 
      and column_name = columnname
   ) then
      execute format('alter table %I add column %I %s', tablename, columnname, columntype);
   end if;
end $$;

--step 2: Add a new column, "age" to the demography table and check the new column exists using "pr_add_new_column_to_table" new procedure
call pr_add_new_column_to_table('demography', 'age', 'integer');

--step 3: Created a new function to get a random number between min and max values
create or replace function get_random_number_between_range(min_value int, max_value int) 
   returns int as
$$
begin
   return floor( random() * (max_value - min_value + 1) + min_value );
end;
$$ language 'plpgsql' strict;

---Step 4: Update the age column with random values within the age group
update public.demography
set age = get_random_number_between_range(split_part(agecat,'-', 1)::int, split_part(agecat,'-', 2)::int);

--Test 
select age, agecat from public.demography;

 
--Q2. Calculate patient's year of birth using admission date from the hospitalization_discharge and add to the demography table.

--step 1:Add a new column(year_of_birth) to demography table using pr_add_new_column_to_table
call pr_add_new_column_to_table('demography', 'year_of_birth', 'integer');

--step 2: Update year_of_birth column based on admission_date and age
update public.demography d
set year_of_birth = extract(year from hd.admission_date)-d.age from public.hospitalization_discharge hd
where d.inpatient_number = hd.inpatient_number;

--Test 
select year_of_birth, age from public.demography;


--Q3. Create a User defined function that returns the age in years of any patient as a calculation from year of birth
--Step1: To get a age from years of any patient as a calculation from year of birth
create or replace function fn_get_age(year_of_birth int) 
   returns int as
$$
begin
   return extract(year from current_date) - year_of_birth;
end;
$$ language 'plpgsql' strict;

--step 2: Test - call the function
select fn_get_age(2013);


--Q4. What % of the dataset is male vs female?
select gender, round((count(*) * 100.00) / (select count(*) from public.demography where gender is not null), 2) as percentage
from public.demography group by gender having gender is not null;


--Q5.How many patients in this dataset are farmers?
select count(*) from public.demography where lower(occupation) = 'farmer';

--Q6. Group the patients by age category and display it as a pie chart

\set width 50
\set height 20
\set radius 1.0
\set colours '''#;o:x"@+-=123456789abcdef'''
with slices as (
select cast(
row_number() over () as integer) as slice,param1,param2,param3,value,100.0 * value /
sum(value) over () as percentage,
2*pi()* sum(value) over (rows unbounded preceding) / sum(value) over ()
as radians from
(
   select 'age category',agecat, 'no of patients', count(*) as no_of_patients from public.demography 
    where agecat is not null group by agecat order by agecat
)
as data(param1,param2,param3, value))
(select array_to_string(array_agg(c),'') as "pie chart - patients by age category"
from (select x, y,
case when not (sqrt(pow(x, 2) + pow(y, 2)) between 0.0 and :radius)
then ' '
else substring(:colours,
(select min(slice) from slices where radians >= pi() + atan2(y,-x)), 1)
end as c
from(select 2.0*generate_series(0,:width)/:width-1.0) as x(x),
(select 2.0*generate_series(0,:height)/ :height-1.0) as y(y)
order by y,x) as xy
group by y
order by y
)
union all
select repeat(substring(:colours,slice,1), 2) || ' ' ||
param1 || ' : ' ||
param2 || ' : ' ||
param3 || ' : ' ||
value || ' : ' ||
round(percentage,0) || '%'
from slices;

--Q7. Divide BMI into slabs of 5 and show the count of patients within each one, without using case statements.

with bmi_slabs as (
select 
	floor(bmi / 5) * 5 as start_slab,
	inpatient_number from demography
)
select start_slab,start_slab + 5 as end_slab, count(inpatient_number) as patient_count
from bmi_slabs group by start_slab order by start_slab;

--Q8. What % of the dataset is over 70 years old
select round((count(*)* 100.00)/ (select count(*) from public.demography), 2) as "patient over 70" from public.demography where age > 70;

--Q9. What age group was least likely to be readmitted within 28 days
select agecat, count(*) from demography 
inner join hospitalization_discharge on demography.inpatient_number = hospitalization_discharge.inpatient_number
where hospitalization_discharge.re_admission_within_28_days = 0 group by agecat order by count(*) asc limit 1;

--Q10. Create a procedure to insert a column with a serial number for all rows in demography.
create or replace procedure pr_add_serial_number()
language plpgsql
as $$
begin
call pr_add_new_column_to_table('demography', 'serial_number', 'serial'); -- used pr_add_new_column_to_table procedure to insert a column
end $$;

-- Execute the procedure
call pr_add_serial_number();
-- Verify the result
select inpatient_number, serial_number from public.demography order by serial_number;

--Q11.what was the average time to readmission among men?
select round(avg(hd.readmission_time_days_from_admission)) as readmission_average_time
from public.demography d
join public.hospitalization_discharge hd on d.inpatient_number = hd.inpatient_number
where lower(d.gender) = 'male' and hd.readmission_time_days_from_admission is not null;

--Q12. Display NYHA_cardiac_function_classification as Class I: No symptoms of heart failure
--Class II: Symptoms of heart failure with moderate exertion
--Class III: Symptoms of heart failure with minimal exertion  and show the most common type of heart failure for each classification

with nyha_classification_function as (
select * from (values
    (1, 'class i: no symptoms of heart failure'),
    (2, 'class ii: symptoms of heart failure with moderate exertion'),
    (3, 'class iii: symptoms of heart failure with minimal exertion')
) as nyhacd(nyha_class, classification))
select
  nyhacd.classification as nyha_classification,
  coalesce(heart_failure_rank.type_of_heart_failure, '') as "common type of heart failure"
from
  nyha_classification_function as nyhacd
left join (
  select cc.nyha_cardiac_function_classification,
cc.type_of_heart_failure,
row_number() over (partition by cc.nyha_cardiac_function_classification order by count(*) desc) as rank
from public.cardiaccomplications cc
group by cc.nyha_cardiac_function_classification, cc.type_of_heart_failure
)as heart_failure_rank
on nyhacd.nyha_class = heart_failure_rank.nyha_cardiac_function_classification and heart_failure_rank.rank = 1;

--Q13. Identify any columns relating to echocardiography and create a severity score for cardiac function. Add this column to the table

--step 1: add new column cardiac_function_severity_score using pr_add_new_column_to_table
call pr_add_new_column_to_table('cardiaccomplications', 'cardiac_function_severity_score', 'integer');

--step 2 : update cardiac_function_severity_score coulmn value, finding the score based on lvef, nyha_cardiac_function_classification and killip_grade
update public.cardiaccomplications
set cardiac_function_severity_score = (
(
case 
   when nyha_cardiac_function_classification = 1 then 0
   when nyha_cardiac_function_classification = 2 then 1
   when nyha_cardiac_function_classification = 3 then 2
   when nyha_cardiac_function_classification = 4 then 3 
   else 0 
end +
case 
   when killip_grade = 1 then 0
   when killip_grade = 2 then 1
   when killip_grade = 3 then 2
   when killip_grade = 4 then 3 
   else 0 
end)
);

 
-- Test Query
select inpatient_number, cardiac_function_severity_score from public.cardiaccomplications;


--Q14. What is the average height of women in cms?

select round(avg(height * 100)) as "average-height_of_women_in_cms" 
from public.demography where lower(gender) = 'female' and height is not null;

--Q15. Using the cardiac severity column from q13, find the correlation between hospital outcomes and cardiac severity

select corr(cardiac_function_severity_score, 
	case 
		 when lower(hd.outcome_during_hospitalization) = 'dead' then 0
		 when lower(hd.outcome_during_hospitalization) = 'alive' then 1
		 when lower(hd.outcome_during_hospitalization) = 'dischargeagainstorder' then 2
		 else null 
	 end
) as correlation from public.hospitalization_discharge hd
join 
public.cardiaccomplications c on hd.inpatient_number = c.inpatient_number;

--Q16. Show the no. of patients for everyday in March 2017. Show the date in March along with the days between the previous recorded day in march and the current.

with daily_patients as (
   select admission_date::date as date,count(*) as patient_count from public.hospitalization_discharge
   where admission_date >= '2017-3-1' and 
	admission_date < '2017-4-1' group by admission_date::date order by date
),
date_diff as (
   select date,patient_count,lag(date) over (order by date) as previous_date from daily_patients
)
select date,patient_count,coalesce((date - previous_date)::integer, 0) as days_between
from date_diff order by date;

--Q17. Create a view that combines patient demographic details of your choice along with pre-existing heart conditions like MI,CHF and PVD

create view cardiac_patient as
select 
 d.inpatient_number,
 d.gender,
 d.age,
 c.congestive_heart_failure,
 c.myocardial_infarction,
 c.peripheral_vascular_disease
 from 
 public.demography d
 
inner join 
 public.cardiaccomplications c 
 on d.inpatient_number = c.inpatient_number;

--Q18. Create a function to calculate the total number of unique patients for every drug. Results must be returned as long as the first few characters match the user input.

create or replace function unique_ptn_cnt_by_drug(ch_of_drug text)
returns table(drug_name text, unique_ptn_cnt int)
language plpgsql
as $$
begin
return Query
select 
pp.drug_name,
count(distinct pp.inpatient_number )::int as unique_ptn_cnt
from 
public.patient_precriptions pp 
where pp.drug_name ilike ch_of_drug ||'%'
group by 
pp.drug_name;
end $$; 

--get the drug name by using select query
select * from unique_ptn_cnt_by_drug('Ato');

--Q19. break up the drug names in patient_precriptions at the ""spaces"" and display only the second string without using Substring.Show unique drug names along with newly broken up string.
select distinct drug_name,split_part(drug_name,' ',2) AS string from public.patient_precriptions;

--Q20.  Select the drug names starting with E and has x in any position after.
select drug_name
from patient_precriptions
where drug_name ilike 'e%x%';

--Q21.Create a cross tab to show the count of readmissions within 28 days, 3 months,6 months as rows and admission ward as columns.
create extension if not exists tablefunc;
select *
from crosstab(
$$
 select 're_admission_within_28_days' as readmission, admission_ward, COUNT(*) 
 from hospitalization_discharge
 where re_admission_within_28_days is not null
 group BY admission_ward
  union all
  select 're_admission_within_3_months' as readmission, admission_ward, COUNT(*) 
  from hospitalization_discharge
  where re_admission_within_3_months is not null
  group by admission_ward
  union all
   select 're_admission_within_6_months' as readmission, admission_ward, COUNT(*) 
   from hospitalization_discharge
   where re_admission_within_6_months is not null
   group by admission_ward
   $$,
'select distinct admission_ward from hospitalization_discharge order by admission_ward'
) as re_admission_cross_tab (readmission text, Cardiology int, GeneralWard int, Others int,ICU int);

--Q22. Create a trigger to stop patient records from being deleted from the demography table.
create or replace function prevent_deletion()
returns trigger as $$
begin
    raise exception 'deletion of patient records is not allowed';
    return null; -- prevents the deletion
end;
$$ 
language plpgsql;
create trigger prevent_patient_deletion
before delete on demography
for each row
execute function prevent_deletion();
delete from demography where year_of_birth = 1948; 

--Q23. What is the total number of days between the earliest admission and the latest.
select 
    max(admission_date) - min(admission_date) as total_days
from 
   hospitalization_discharge;

--Q24. Divide discharge day by visit times for any 10 patients without using mathematical operators like '/'

with patient_data as (
select inpatient_number,dischargeday , visit_times
 from hospitalization_discharge
limit 10
)
select 
inpatient_number ,
dischargeday,
visit_times,
case 
when visit_times = 0 then null -- avoid division by zero
else dischargeday * (1.0 / visit_times) -- using multiplication by reciprocal
end as discharge_per_visit
from patient_data;

--Q25.Show the count of patients by first letter of admission_way.

select 
substring(admission_way from 1 for 1) as first_letter,
count(*) as inpatient_number
from 
hospitalization_discharge 
group by 
first_letter;

--Q26. Display an array of personal markers:gender, BMI, pulse, MAP for every patient. The result should look like this.

select distinct d.inpatient_number,
array[d.gender,to_char(d.bmi,'fm999999999.00'),l.pulse :: text,to_char(l.map_value,'fm999999999.00')] as markers
from demography d
join labs l on d.inpatient_number = l.inpatient_number;

--Q27.  Display medications With Name contains 'hydro' and display it as 'H20'.
select 
    distinct drug_name as "H20"
from 
   patient_precriptions 
where 
    drug_name ilike '%hydro%';

--Q28.  Create a trigger to raise notice and prevent deletion of the view created in question 17.
--Delete triggers can be used for DML operatins.In this question we need to use event trigger to perform DDL operatins(like views).

--Step 1 - Create a trigger function
create or replace function pre_delete_from_dwh()
returns event_trigger
language plpgsql
as $$
begin
 raise exception 'deleting this view is not allowed';
end $$;

--Step 2 - Create the event trigger
create event trigger trig_for_dwh
on sql_drop
execute function pre_delete_from_dwh();

--Step 3 - testing the trigger
drop view cardiac_patient;


--Q29.  How many unique patients have cancer?
--Leukemia,malignant_lymphoma and solid_tumor are the types of cancer. But not all the solid tumors are not cancer.So here we have taken only leukemia and malignant_lymphoma.

select count(distinct inpatient_number) as unique_cancer_patients
from patienthistory
where malignant_lymphoma = 1 or leukemia=1;

--Q30. Show the moving average of number of patient admitted every 3 months.
select 
    date_trunc('month', admission_date) as admission_month,
    count(*) as number_of_patients,
    avg(count(*)) over (
        order by date_trunc('month', admission_date) 
    ) as moving_average
from 
   hospitalization_discharge 
group by 
    admission_month;

--Q31. Write a  to get a list of patient IDs' who recieved oxygen therapy and had a high respiration rate in February 2017.
select hd.inpatient_number,hd.admission_date,l.respiration from hospitalization_discharge as hd
inner join public.labs as l 
 on hd.inpatient_number = l.inpatient_number
 where hd.oxygen_inhalation = 'oxygentherapy'
 and extract(year from hd.admission_date) = 2017
 and extract(month from hd.admission_date) = 2
 and l.respiration >'20';

--Q32.Display patients with heart failure type: "both" along with highest MAP and highest pulse without using limit. 
with maxvalues as (
    select 
        inpatient_number,
        max(map_value) as max_map,
        max(pulse) as max_pulse
    from labs
    group by inpatient_number
)
select c.inpatient_number,c.type_of_heart_failure,mv.max_map, mv.max_pulse
from cardiaccomplications c
join maxvalues mv on c.inpatient_number = mv.inpatient_number
where c.type_of_heart_failure = 'both';

--Q33. Create a stored procedure that displays any message on the screen without using any tables/views.
create or replace procedure pr_message()
language plpgsql
as $$
begin
    raise notice 'Sql Hackathon Sep-2024';
end
$$;

-- Test Call procedure
call pr_message();

--Q34. In healthy people, monocytes make up about 1%-9% of total white blood cells. Calculate avg monocyte percentages among each age group.
select 
d.agecat as age_category, 
round(cast(avg(l.monocyte_count) as numeric), 2) as average_monocite_count,
round(avg((cast(l.monocyte_count as numeric) / cast(l.white_blood_cell as numeric)) * 100), 2) as average_monocite_percentage
from public.labs l, public.demography d
where l.inpatient_number = d.inpatient_number and agecat is not null
group by d.agecat 
order by d.agecat;

--Q35. Create a table that stores any Patient Demographics of your choice as the parent table. Create a child table that contains systolic_blood_pressure, diastolic_blood_pressure per patient and inherits all columns from the parent table.

--Step 1 : Creating parent Table:
create table parent_demography(
    inpatient_number int not null,
    gender varchar (10),
    weight int,
    height int,
    primary key(inpatient_number)
);

--Step 2: Creating Child Table:
create table child_demography(
    systolic_blood_pressure int,
    diastolic_blood_pressure int) 
inherits (parent_demography);


-- Test 
select * from public.child_demography;

--Q36. Write a select statement with no table or view attached to it.
select 100 as employee_number,'Kasthuri Indiran' as display_name,'DA120' as batch_Number,  'sql hackathon' as work_type ,'Numphy Ninja' as organization;

--Q37. Create a re-usable function to calculate the percentage of patients for any group. Use this function to calculate % of patients in each admission ward.
create or replace function percentage_calc_for_a_group(p_group text) 
returns numeric
language 'plpgsql'
as $$
declare
grp_count integer;
total integer;
percentage numeric;
begin
select count(*) into total from public.hospitalization_discharge;
if total = 0 then 
return 0;
end if;
select count(*) into grp_count from public.hospitalization_discharge 
where   admission_ward=p_group;
if grp_count = 0 then
return 0;
end if;
percentage=(grp_count::decimal/total)*100;
return round(percentage,2);
end $$;

-- Test 
select percentage_calc_for_a_group('GeneralWard');

--Q38. Write a  that shows if CCI score is an even or odd number for any 10 patients.
select inpatient_number,cci_score,
case
when mod(cci_score::int,2) = 0 then 'even'
else 'odd'
end 
as cci_type
from public.patienthistory
limit(10);


--Q39. Using windows functions show the number of hospitalizations in the previous month and the next month.
with month_counts as(select DATE_TRUNC('month',admission_date) as admission_month,
        sum(visit_times) as hospital_stay
from  hospitalization_discharge
group by DATE_TRUNC('month', admission_date)
)select admission_month, hospital_stay as current_month_hospitalizations,
 lag(hospital_stay, 1) over (order by admission_month) as previous_month_hospitalizations,
    lead(hospital_stay, 1) over (order by admission_month) as next_month_hospitalizations
from  month_counts;


--Q40. Write a function to get comma-separated values of patient details based on patient number entered by the user. (Use a maximum of 6 columns from different tables)
create or replace function display_patient_details(patient_num integer)
returns text
language plpgsql
as
$$
declare
patient_details text;
begin
select string_agg(patient_values,',') into patient_details
from (select d.gender||','||hd.visit_times||','||l.body_temperature||','||cc.nyha_cardiac_function_classification||','||ph.cci_score||','||r.verbal_response as patient_values
from demography d
inner join hospitalization_discharge hd using (inpatient_number)
inner join labs l using(inpatient_number)
inner join cardiaccomplications cc using(inpatient_number)
inner join patienthistory ph using(inpatient_number)
inner join responsivenes r using(inpatient_number)
where d.inpatient_number = patient_num
)as details;
return patient_details;
end
$$;

--Calling function:
select display_patient_details(722128);

--Q41. Which patients were on more than 15 prescribed drugs? What was their age and outcome? show the results without using a sub.
select d.inpatient_number,d.age,hd.outcome_during_hospitalization
from demography d
join hospitalization_discharge hd on d.inpatient_number= hd.inpatient_number
join patient_precriptions pp on d.inpatient_number= pp.inpatient_number
group by d.inpatient_number,d.age,hd.outcome_during_hospitalization
having count(pp.drug_name)>15;

--Q42. Write a PLSQL block to return the patient ID and gender from demography for a patient if the ID exists and raise an exception if the patient id is not found. Do this without writing or storing a function. Patient ID can be hard-coded for the block
do
$$
declare
  input_patient_id int := 722128;
  patient_id int;
  patient_gender text;
begin
	select inpatient_number,gender into patient_id,patient_gender from demography where inpatient_number = input_patient_id;
    if patient_id is null then
    	raise exception 'Patient ID % is not found', input_patient_id;
	else
		raise notice 'Patient ID: % is found and the Gender is : %', patient_id, patient_gender;
	end if;
end
$$;

 
--Q43. Display any 10 random patients along with their type of heart failure.
select d.inpatient_number,cc.type_of_heart_failure
from demography d
join cardiaccomplications cc on d.inpatient_number=cc.inpatient_number
order by random()
limit(10);


--Q44. How many unique drug names have a length >20 letters?
select count(distinct drug_name) as count_of_long_name_drugs
from patient_precriptions
where length(drug_name)>20;


--Q45. Rank patients using CCI Score as your base. Use a windows function to rank them in descending order. With the highest no. of comorbidities ranked 1.
select inpatient_number,cci_score,
dense_rank() over(order by cci_score desc) as rank_num
from patienthistory
where cci_score is not null;


--Q46. What ratio of patients who are responsive to sound vs pain?
with cnt_of_res as (select(select count(*)from responsivenes where consciousness='ResponsiveToSound') as sound_res,
 (select count(*)from responsivenes where consciousness='ResponsiveToPain')as pain_res)
 select sound_res,pain_res,(cast(sound_res as float)/nullif(pain_res,0)) as ratio 
 from cnt_of_res
 limit(1);

--Q47. Use a windows function to return all admission ways along with occupation which is related to the highest MAP value
with highest_map_value as (
select d.occupation,l.map_value,hd.admission_way,
row_number() over (partition by d.occupation order by l.map_value desc) as ranked
from demography d
join labs l on d.inpatient_number=l.inpatient_number
join hospitalization_discharge hd on d.inpatient_number=hd.inpatient_number
)	
select occupation,map_value,admission_way
from highest_map_value
where occupation is not null and ranked=1;

--Q48. Display the patients with the highest BMI.
select inpatient_number , bmi as highest_bmi from demography
order by bmi desc
limit 1;

--Q49. Find the list of Patients who has leukopenia.
select * from demography d 
inner join labs l on l.inpatient_number = d.inpatient_number
where l.white_blood_cell <=4;

--Q50. What is the most frequent weekday of admission?
select  to_char(admission_date,'Day') as weekday, count(*) as frequency
from hospitalization_discharge
group by to_char(admission_date,'Day')
order by frequency desc
limit 1;

--Q51. Create a console bar chart using the '▰' symbol for count of patients in any age category where theres more than 100 patients
select count(*) as patientcount, agecat, repeat('▰',cast(count(*) as int)) as repeat from demography
group by agecat having count(*) > 100 order by patientcount desc;

--Q52. Find the variance of the patients' D_dimer value and display it along with the correlation to CCI score and display them together.
select variance(l.d_dimer), corr(p.cci_score, l.d_dimer) from labs l inner join patienthistory p on
  p.inpatient_number = l.inpatient_number;

--Q53. Which adm ward had the lowest rate of Outcome Death?
with death_in_ward as(
select admission_ward, 
count(*) AS death_cnt 
from hospitalization_discharge
where outcome_during_hospitalization = 'Dead'
group by admission_ward
),
total_cnt_ward as(
select admission_ward, 
count(*) AS total_cnt_patients
from hospitalization_discharge
group by admission_ward
)
select death_in_ward .admission_ward, 
(death_in_ward .death_cnt * 1.0 / total_cnt_ward .total_cnt_patients) AS death_rate
from death_in_ward 
join total_cnt_ward 
on death_in_ward .admission_ward = total_cnt_ward .admission_ward
order by death_rate asc
limit 1;	
	 		
--Q54. What % of those in a coma also have diabetes. Use the GCS scale to evaluate.
select ((select count(*) from patienthistory p 
inner join responsivenes r on r.inpatient_number = p.inpatient_number
where p.diabetes = 1 and r.gcs < 15 ) * 100.0)/ (select count(*) from patienthistory)
as como_dia_percent;

--Q55. Display the drugs prescribed for the youngest patient
select p.inpatient_number,d.age , string_agg(distinct drug_name, ' , ') as drugname 
from patient_precriptions p  
inner join demography d on d.inpatient_number = p.inpatient_number 
where d.age =(select min(age) from demography)
 group by p.inpatient_number,d.age;

--Q56. Create a view on the public.responsivenes table using the check constraint
create view resp_view as
select * from responsivenes
where gcs< 10 and consciousness = 'ResponsiveToSound'
with check option;
-- test
select * from resp_view;
--test
drop view resp_view;

--Q57. Determine if a word is a palindrome and display true or false. Create a temporary table and store any words of your choice for this question
--create table
create table temp(
ind int,
words text);

-- insert records
insert into temp(ind, words)
values('1', 'rotator'),
      ('2','potato'),
      ('3','kayak'),
      ('4','madam'),
      ('5','level');

--test
select words, case
when words = reverse(words) then 'TRUE'
else 'FALSE'
end from temp;

--Q58. How many visits were common among those with a readmission in 6 months
select avg(visit_times) as average_visit_time from hospitalization_discharge 
where re_admission_within_6_months =1 group by re_admission_within_6_months;

--Q59. What is the size of the database Cardiac_Failure
select pg_size_pretty(pg_database_size('Cardiac_Failure')) as size;


--Q60. Find the greatest common denominator and the lowest common multiple of the numbers 365 and 300. show it in one 
select gcd(365,300), lcm(365,300);

--Q61. Group patients by destination of discharge and show what % of all patients in each group was re-admitted within 28 days.Partition these groups as 2: high rate of readmission, low rate of re-admission. Use windows functions
with re_admit_patient as (
select destinationdischarge, count(1) as total_patients,
sum(case when re_admission_within_28_days = 1 then 1 else 0 end) as re_admit_cnt
from
hospitalization_discharge
group by
destinationdischarge
)
select destinationdischarge,total_patients,re_admit_cnt,
round(re_admit_cnt * 100.0 / total_patients, 2) as re_admint_pct,
case
when (re_admit_cnt * 100.0 / total_patients) > 30 then 'high admission rate' else 'low admission rate'
end as re_admit_type
from
re_admit_patient;

--Q62. What is the size of the table labs in KB without the indexes or additional objects
SELECT pg_size_pretty(pg_table_size('labs')) AS tablesize;

--Q63. concatenate age, gender and patient ID with a ';' in between without using the || operator
select concat(inpatient_number,' ; ',age,' ; ',gender) as Concat from demography;

--Q64. Display a reverse of any 5 drug names
select reverse(drug_name) from patient_precriptions limit 5;

--Q65. What is the variance from mean for all patients GCS score
WITH mean_GCS AS (
SELECT 
AVG(GCS) AS mean_value
FROM 
responsivenes)
SELECT 
r.gcs,
(r.gcs - m.mean_value) AS variance_from_mean,
(r.gcs - m.mean_value) ^ 2 AS squared_variance_from_mean
FROM 
responsivenes r, mean_gcs m;

--Q66. Using a while loop and a raise notice command, print the 7 times table (multiplication table for the number 7, from 7x1 to 7X9) as the result
Do
$$
DECLARE
i INT := 1; 
BEGIN
WHILE i <= 9 LOOP
RAISE NOTICE '% x 7 = %', i, i * 7;  
i := i + 1; 
END LOOP;
END $$;

--Q67. show month number and month name next to each other(admission_date), ensure that month number is always 2 digits. eg, 5 should be 05"
SELECT 
inpatient_number,
TO_CHAR(admission_date, 'MM') AS month_number,
TO_CHAR(admission_date, 'Month') AS month_name 
FROM 
hospitalization_discharge;

--Q68. How many patients with both heart failures had kidney disease or cancer.
select count(distinct pp.inpatient_number) as pat_cnt
from patienthistory pp
join cardiaccomplications cc on pp.inpatient_number=cc.inpatient_number
where cc.type_of_heart_failure='Both' and (pp.moderate_to_severe_chronic_kidney_disease=1 or pp.malignant_lymphoma=1);

--Q69. Return the number of bits and the number of characters for every value in the column: Occupation
select occupation,
length(occupation) as num_of_char,
length(occupation)*8 as num_of_bits
from demography;

--Q70. Create a stored procedure that adds a column to table cardiaccomplications. The column should just be the todays date
--Step1:
create or replace procedure add_column()
language plpgsql
as $$
begin
 alter table cardiaccomplications
 add column today_date date default current_date;
end
$$;

--Step 2:
call add_column();

--step 3:
select * from cardiaccomplications;

--Q71 . What is the 2nd highest BMI of the patients with 5 highest myoglobin values. Use windows functions in solution
with second_bmi as (select d.inpatient_number,l.myoglobin,d.bmi 
from labs l
join demography d on d.inpatient_number=l.inpatient_number
where l.myoglobin is not null 
order by l.myoglobin desc
offset 1 limit(1))
select sb.myoglobin,sb.bmi
from second_bmi sb;

--Q72. What is the standard deviation from mean for all patients pulse
SELECT 
AVG(pulse) AS mean_pulse,
STDDEV(pulse) AS sdev_pulse
FROM 
labs;

--Q73. Create a procedure to drop the age column from demography
--step1
create or replace procedure drop_age_column()
language plpgsql
as $$
begin
if exists (
      select 1
      from information_schema.columns
      where table_name = 'demography'
      and column_name = 'age'
   ) then
  execute 'alter table demography drop column age';
end if;
end
$$;
--step2
call drop_age_column();
--step3
select * from demography;


--Q74. What was the average CCI score for those with a BMI>30 vs for those <30
SELECT 
    AVG(CASE WHEN d.bmi > 30 THEN p.cci_score END) AS avg_cci_bmi_above_30,
    AVG(CASE WHEN d.bmi <= 30 THEN p.cci_score END) AS avg_cci_bmi_below_30
FROM 
    demography d
FULL JOIN 
    patienthistory p ON d.inpatient_number = p.inpatient_number;

--Q75. Write a trigger after insert on the Patient Demography table. if the BMI >40, warn for high risk of heart risks

--step1
CREATE OR REPLACE FUNCTION warn_for_high_risk_of_heart_risks()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$ BEGIN
    IF NEW.bmi > 40 THEN
        RAISE WARNING 'High risk of heart risks for patient with inpatient_number: %', NEW.inpatient_number;
    END IF;
    RETURN NEW;
END 
$$;
--step2
create trigger high_risk_bmi
after insert on demography
for each row
execute function warn_for_high_risk_of_heart_risks();
--step3
insert into demography(inpatient_number, bmi)
values(444444444, 41);


--Q76. Most obese patients belong to which age group and gender. You may make an assumption for what qualifies as obese based on your research
SELECT 
    d.gender,
    d.agecat,
    COUNT(*) AS number_of_people
FROM 
    demography d
WHERE 
    bmi > 30 
GROUP BY 
    d.gender, d.agecat
ORDER BY 
   d. gender, d.agecat;

--As per data  Female aged 79-89 are obse;

--Q77. Show all response details of a patient in a JSON array
SELECT json_agg(inpatient_number) FROM responsivenes;

--Q78. Update the table public.patienthistory. Set type_ii_respiratory_failure to be upper case, the results of the updated table without writing a second 
UPDATE public.patienthistory
	SET  type_ii_respiratory_failure = 'TYPE_II_RESPIRATORY_FAILURE'
	RETURNING *;

--Q79.  Find all patients using Digoxin or Furosemide using regex
SELECT inpatient_number, drug_name
FROM public.patient_precriptions where drug_name ~*'^(Digoxin tablet|Furosemide tablet|Furosemide injection|Digoxin injection)$';

--Q80. Using a recursive , show any 10 patients linked to the drug: "Furosemide injection"
SELECT inpatient_number, drug_name
	FROM public.patient_precriptions where drug_name ='Furosemide injection'
	Limit 10;