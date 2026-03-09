COPY (
  select
    id,
    base_path,
    title,
    details->'body' as body,
    expanded_links->'taxons' as taxons
  from content_items
  where publishing_app = 'whitehall'
  and expanded_links?'taxons'
  order by id asc
  limit 50
) to STDOUT WITH CSV HEADER;
