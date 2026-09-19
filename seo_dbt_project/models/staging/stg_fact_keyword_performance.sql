-- Vista staging sobre la fact legacy (fuente: source('legacy', 'fact_keyword_performance'))
with source as (
    select * from {{ source('legacy', 'fact_keyword_performance') }}
)

select
    fact_id,
    date_id,
    keyword_id,
    search_volume,
    keyword_difficulty,
    current_position,
    estimated_ctr,
    estimated_traffic
from source
