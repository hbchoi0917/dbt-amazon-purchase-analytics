with source as (
    select * from {{ source('open_ecommerce', 'survey') }}
)

-- Only the demographic and Amazon-usage questions are selected. Health, substance-use,
-- race and sexual-orientation answers are deliberately left out: they are not needed
-- for spend analysis and the dataset authors ask that participants not be re-identified.
select
    "Survey ResponseID"       as customer_id,
    "Q-demos-age"             as age_group,
    case "Q-demos-age"
        when '18 - 24 years' then 1
        when '25 - 34 years' then 2
        when '35 - 44 years' then 3
        when '45 - 54 years' then 4
        when '55 - 64 years' then 5
        when '65 and older' then 6
    end                       as age_group_order,
    "Q-demos-income"          as income_band,
    case "Q-demos-income"
        when 'Less than $25,000' then 1
        when '$25,000 - $49,999' then 2
        when '$50,000 - $74,999' then 3
        when '$75,000 - $99,999' then 4
        when '$100,000 - $149,999' then 5
        when '$150,000 or more' then 6
        when 'Prefer not to say' then 7
    end                       as income_band_order,
    "Q-demos-education"       as education_level,
    "Q-demos-gender"          as gender,
    "Q-demos-state"           as home_state,
    "Q-amazon-use-hh-size"    as household_size,
    "Q-amazon-use-howmany"    as account_users,
    "Q-amazon-use-how-oft"    as self_reported_order_frequency
from source
