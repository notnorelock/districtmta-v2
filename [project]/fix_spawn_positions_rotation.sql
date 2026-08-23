SELECT
    id,
    name,
    spawn_positions AS original,
    (
        SELECT JSON_ARRAYAGG(
            JSON_ARRAY(
                JSON_EXTRACT(pt.value, '$[0]'),
                JSON_EXTRACT(pt.value, '$[1]'),
                JSON_EXTRACT(pt.value, '$[2]'),
                JSON_EXTRACT(pt.value, '$[4]'),
                JSON_EXTRACT(pt.value, '$[5]'),
                JSON_EXTRACT(pt.value, '$[3]')
            )
        )
        FROM JSON_TABLE(
            spawn_positions,
            '$[*]' COLUMNS (value JSON PATH '$')
        ) AS pt
    ) AS corrected
FROM vehicle_stores;

UPDATE vehicle_stores
SET spawn_positions = (
    SELECT JSON_ARRAYAGG(
        JSON_ARRAY(
            JSON_EXTRACT(pt.value, '$[0]'),
            JSON_EXTRACT(pt.value, '$[1]'),
            JSON_EXTRACT(pt.value, '$[2]'),
            JSON_EXTRACT(pt.value, '$[4]'),
            JSON_EXTRACT(pt.value, '$[5]'),
            JSON_EXTRACT(pt.value, '$[3]')
        )
    )
    FROM JSON_TABLE(
        spawn_positions,
        '$[*]' COLUMNS (value JSON PATH '$')
    ) AS pt
)
WHERE spawn_positions IS NOT NULL
  AND JSON_LENGTH(spawn_positions) > 0;
