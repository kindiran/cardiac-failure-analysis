--EQ1.Find the drug which has been prescribed very often for patients who are admitted?
select drug_name,count(*) as drug_cnt
from patient_precriptions
group by drug_name
order by drug_cnt desc
limit(1);

--EQ2. Name the drug which has been prescribed commonly for patients who were in very critical conditions.
with max_drug_cnt as(
select pp.drug_name,count(*)as dgr_cnt
from patient_precriptions pp
join hospitalization_discharge ph on ph.inpatient_number=pp.inpatient_number
where ph.outcome_during_hospitalization = 'Dead'
group by drug_name
order by dgr_cnt desc
)
select pp.drug_name,ph.outcome_during_hospitalization,mdc.dgr_cnt
from patient_precriptions pp
join hospitalization_discharge ph on ph.inpatient_number=pp.inpatient_number
join max_drug_cnt mdc on pp.drug_name=mdc.drug_name
where ph.outcome_during_hospitalization='Dead'
order by mdc.dgr_cnt desc
limit(1);
 
--EQ3. Add a column in the demographic table random of 4 numbers, but it should be encrypted, and the key should be the year of birth and display the encrypted and decrypted number.
-- step1: create extension if not exists
create extension if not exists pgcrypto;

-- step 2: add new column
do $$
begin
    if not exists (
        select 1 from information_schema.columns
        where table_name = 'demography' and column_name = 'encrypted_four_digit_number'
    ) then
        alter table public.demography
        add column encrypted_four_digit_number bytea;
    end if;
end
$$;

 -- step 3: UPDATE demography
update demography
set encrypted_four_digit_number = pgp_sym_encrypt(
    (trunc(random() * 9000 + 1000)::int)::text,
    year_of_birth::text
);

--Test Query:
select encrypted_four_digit_number, pgp_sym_decrypt(encrypted_four_digit_number, year_of_birth::text) as decrypted_random_number
from demography;

--EQ4. How many millennial patients are discharged within a week group by gender?
select gender, count(*) as millennial_patients_discharged_in_week from 
public.demography d
join
public.hospitalization_discharge hd
on d.inpatient_number = hd.inpatient_number where year_of_birth between 1981 and 1996 and hd.dischargeday <= 7 group by gender;

--EQ5. Most commonly used prescriptions among men over 80 years.
select p.drug_name,count(p.drug_name) as prescription_count
from demography d
join public.patient_precriptions  p on d.inpatient_number = p.inpatient_number
where d.gender = 'Male' and d.age > 80
group by p.drug_name order by prescription_count desc;
 
--EQ6. Find the top 5 patients with the highest creatinine levels and list their corresponding urea levels.
select inpatient_number, creatinine_enzymatic_method, urea
from labs
where creatinine_enzymatic_method is not null order by creatinine_enzymatic_method desc
limit 5;
 
--EQ7. Patient admission count by year and gender
select extract(year from admission_date) as year, gender, count(*) as no_of_patients from demography d
join public.hospitalization_discharge hd on d.inpatient_number = hd.inpatient_number 
group by year, d.gender order by year;

--EQ8.Find the type of  heart failure which has a highest count of readmission within 3months.
select cc.type_of_heart_failure, count(*) as count_of_readmission_within_3_months
from cardiaccomplications cc
join hospitalization_discharge h on cc.inpatient_number = h.inpatient_number
where h.re_admission_within_3_months = 1
group by cc.type_of_heart_failure
order by count_of_readmission_within_3_months desc
limit(1); 
