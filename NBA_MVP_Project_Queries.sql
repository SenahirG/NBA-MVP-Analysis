USE NBA_MVP_Analysis;

SELECT COUNT(*) AS total_rows
FROM dbo.nba_player_stats;

SELECT
    COUNT(*) AS total_rows,
    SUM(
        CASE
            WHEN college IS NULL OR LTRIM(RTRIM(college)) = ''
            THEN 1
            ELSE 0
        END
    ) AS missing_college,
    COUNT(DISTINCT season) AS total_seasons,
    MIN(season_start) AS first_season_year,
    MAX(season_start) AS last_season_year
FROM dbo.nba_player_stats;


UPDATE dbo.nba_player_stats
SET college = 'Unknown'
WHERE college IS NULL
   OR LTRIM(RTRIM(college)) = '';

SELECT @@ROWCOUNT AS rows_updated;



GO

CREATE OR ALTER VIEW dbo.vw_nba_player_stats_clean AS
SELECT *,
    TRY_CONVERT(float, REPLACE(oreb_pct, '%', '')) / 100.0 AS oreb_pct_num,
    TRY_CONVERT(float, REPLACE(dreb_pct, '%', '')) / 100.0 AS dreb_pct_num,
    TRY_CONVERT(float, REPLACE(usg_pct, '%', '')) / 100.0 AS usg_pct_num,
    TRY_CONVERT(float, REPLACE(ts_pct, '%', '')) / 100.0 AS ts_pct_num,
    TRY_CONVERT(float, REPLACE(ast_pct, '%', '')) / 100.0 AS ast_pct_num
FROM dbo.nba_player_stats;

GO



SELECT TOP 5
    player_name,
    oreb_pct,
    oreb_pct_num,
    ts_pct,
    ts_pct_num
FROM dbo.vw_nba_player_stats_clean;



SELECT
    SUM(CASE WHEN oreb_pct_num IS NULL THEN 1 ELSE 0 END) AS invalid_oreb_pct,
    SUM(CASE WHEN dreb_pct_num IS NULL THEN 1 ELSE 0 END) AS invalid_dreb_pct,
    SUM(CASE WHEN usg_pct_num IS NULL THEN 1 ELSE 0 END) AS invalid_usg_pct,
    SUM(CASE WHEN ts_pct_num IS NULL THEN 1 ELSE 0 END) AS invalid_ts_pct,
    SUM(CASE WHEN ast_pct_num IS NULL THEN 1 ELSE 0 END) AS invalid_ast_pct
FROM dbo.vw_nba_player_stats_clean;



GO

CREATE OR ALTER VIEW dbo.vw_nba_player_stats_clean AS
WITH base AS (
    SELECT *,
        MAX(gp) OVER (PARTITION BY season) AS observed_max_gp
    FROM dbo.nba_player_stats
)
SELECT *,
    TRY_CONVERT(float, REPLACE(oreb_pct, '%', '')) / 100.0 AS oreb_pct_num,
    TRY_CONVERT(float, REPLACE(dreb_pct, '%', '')) / 100.0 AS dreb_pct_num,
    TRY_CONVERT(float, REPLACE(usg_pct, '%', '')) / 100.0 AS usg_pct_num,
    TRY_CONVERT(float, REPLACE(ts_pct, '%', '')) / 100.0 AS ts_pct_num,
    TRY_CONVERT(float, REPLACE(ast_pct, '%', '')) / 100.0 AS ast_pct_num,
    CAST(
        CASE
            WHEN gp >= 0.70 *
                CASE
                    WHEN observed_max_gp > 82 THEN 82
                    ELSE observed_max_gp
                END
            THEN 1
            ELSE 0
        END AS bit
    ) AS eligible_calc
FROM base;

GO



WITH ranked_players AS (
    SELECT
        player_name,
        team_abbreviation,
        gp,
        pts,
        reb,
        ast,
        CAST(ts_pct_num * 100 AS decimal(5,1)) AS ts_pct,
        CAST(usg_pct_num * 100 AS decimal(5,1)) AS usage_pct,
        DENSE_RANK() OVER (ORDER BY pts DESC) AS scoring_rank,
        DENSE_RANK() OVER (ORDER BY reb DESC) AS rebounding_rank,
        DENSE_RANK() OVER (ORDER BY ast DESC) AS playmaking_rank
    FROM dbo.vw_nba_player_stats_clean
    WHERE season = '2022-23'
      AND eligible_calc = 1
)
SELECT
    category,
    ranking,
    player_name,
    team_abbreviation,
    gp,
    pts,
    reb,
    ast,
    ts_pct,
    usage_pct
FROM (
    SELECT
        1 AS category_order,
        'Scoring' AS category,
        scoring_rank AS ranking,
        player_name, team_abbreviation, gp, pts, reb, ast,
        ts_pct, usage_pct
    FROM ranked_players
    WHERE scoring_rank <= 5

    UNION ALL

    SELECT
        2,
        'Rebounding',
        rebounding_rank,
        player_name, team_abbreviation, gp, pts, reb, ast,
        ts_pct, usage_pct
    FROM ranked_players
    WHERE rebounding_rank <= 5

    UNION ALL

    SELECT
        3,
        'Playmaking',
        playmaking_rank,
        player_name, team_abbreviation, gp, pts, reb, ast,
        ts_pct, usage_pct
    FROM ranked_players
    WHERE playmaking_rank <= 5
) AS leaders
ORDER BY category_order, ranking, player_name;




WITH ranked_players AS (
    SELECT
        season,
        player_name,
        team_abbreviation,
        gp,
        CAST(pts AS decimal(5,1)) AS pts,
        CAST(reb AS decimal(5,1)) AS reb,
        CAST(ast AS decimal(5,1)) AS ast,
        CAST(ts_pct_num * 100 AS decimal(5,1)) AS ts_pct,
        CAST(usg_pct_num * 100 AS decimal(5,1)) AS usage_pct,
        DENSE_RANK() OVER (
            PARTITION BY season ORDER BY pts DESC
        ) AS scoring_rank,
        DENSE_RANK() OVER (
            PARTITION BY season ORDER BY reb DESC
        ) AS rebounding_rank,
        DENSE_RANK() OVER (
            PARTITION BY season ORDER BY ast DESC
        ) AS playmaking_rank
    FROM dbo.vw_nba_player_stats_clean
    WHERE eligible_calc = 1
)
SELECT
    season,
    category,
    player_name,
    team_abbreviation,
    gp,
    pts,
    reb,
    ast,
    ts_pct,
    usage_pct
FROM (
    SELECT
        season, 1 AS category_order, 'Scoring' AS category,
        player_name, team_abbreviation, gp, pts, reb, ast,
        ts_pct, usage_pct
    FROM ranked_players
    WHERE scoring_rank = 1

    UNION ALL

    SELECT
        season, 2, 'Rebounding',
        player_name, team_abbreviation, gp, pts, reb, ast,
        ts_pct, usage_pct
    FROM ranked_players
    WHERE rebounding_rank = 1

    UNION ALL

    SELECT
        season, 3, 'Playmaking',
        player_name, team_abbreviation, gp, pts, reb, ast,
        ts_pct, usage_pct
    FROM ranked_players
    WHERE playmaking_rank = 1
) AS season_leaders
ORDER BY season, category_order, player_name;





-- Analysis 2: Usage rate versus true-shooting efficiency

WITH usage_groups AS (
    SELECT
        CASE
            WHEN usg_pct_num < 0.15 THEN 'Low usage'
            WHEN usg_pct_num < 0.20 THEN 'Moderate usage'
            WHEN usg_pct_num < 0.25 THEN 'High usage'
            ELSE 'Very high usage'
        END AS usage_group,
        CASE
            WHEN usg_pct_num < 0.15 THEN 1
            WHEN usg_pct_num < 0.20 THEN 2
            WHEN usg_pct_num < 0.25 THEN 3
            ELSE 4
        END AS usage_order,
        usg_pct_num,
        ts_pct_num,
        pts
    FROM dbo.vw_nba_player_stats_clean
    WHERE eligible_calc = 1
      AND usg_pct_num > 0
      AND ts_pct_num > 0
)
SELECT
    usage_group,
    COUNT(*) AS player_seasons,
    CAST(AVG(usg_pct_num) * 100 AS decimal(5,1)) AS avg_usage_pct,
    CAST(AVG(ts_pct_num) * 100 AS decimal(5,1)) AS avg_ts_pct,
    CAST(AVG(pts) AS decimal(5,1)) AS avg_points
FROM usage_groups
GROUP BY usage_group, usage_order
ORDER BY usage_order;




-- Correlation between usage rate and true-shooting percentage

WITH efficiency_data AS (
    SELECT
        usg_pct_num AS usage_rate,
        ts_pct_num AS shooting_efficiency
    FROM dbo.vw_nba_player_stats_clean
    WHERE eligible_calc = 1
      AND usg_pct_num > 0
      AND ts_pct_num > 0
)
SELECT
    COUNT(*) AS player_seasons,
    CAST(
        (
            COUNT(*) * SUM(usage_rate * shooting_efficiency)
            - SUM(usage_rate) * SUM(shooting_efficiency)
        )
        /
        NULLIF(
            SQRT(
                (
                    COUNT(*) * SUM(usage_rate * usage_rate)
                    - POWER(SUM(usage_rate), 2)
                )
                *
                (
                    COUNT(*) * SUM(shooting_efficiency * shooting_efficiency)
                    - POWER(SUM(shooting_efficiency), 2)
                )
            ),
            0
        )
        AS decimal(6,3)
    ) AS usage_efficiency_correlation
FROM efficiency_data;





-- Analysis 3: Most improved players across consecutive seasons

;WITH player_history AS (
    SELECT
        CONCAT(
            player_name, '|', draft_year, '|',
            draft_number, '|', college
        ) AS player_key,
        player_name,
        season,
        season_start,
        pts,
        reb,
        ast,
        eligible_calc
    FROM dbo.vw_nba_player_stats_clean
),
season_comparison AS (
    SELECT
        *,
        LAG(season) OVER (
            PARTITION BY player_key ORDER BY season_start
        ) AS previous_season,
        LAG(season_start) OVER (
            PARTITION BY player_key ORDER BY season_start
        ) AS previous_season_start,
        LAG(pts) OVER (
            PARTITION BY player_key ORDER BY season_start
        ) AS previous_pts,
        LAG(reb) OVER (
            PARTITION BY player_key ORDER BY season_start
        ) AS previous_reb,
        LAG(ast) OVER (
            PARTITION BY player_key ORDER BY season_start
        ) AS previous_ast,
        LAG(eligible_calc) OVER (
            PARTITION BY player_key ORDER BY season_start
        ) AS previous_eligible
    FROM player_history
),
improvements AS (
    SELECT
        player_name,
        previous_season,
        season,
        previous_pts,
        pts,
        previous_reb,
        reb,
        previous_ast,
        ast,
        pts - previous_pts AS pts_improvement,
        reb - previous_reb AS reb_improvement,
        ast - previous_ast AS ast_improvement
    FROM season_comparison
    WHERE season_start = previous_season_start + 1
      AND eligible_calc = 1
      AND previous_eligible = 1
),
ranked_improvements AS (
    SELECT *,
        DENSE_RANK() OVER (
            ORDER BY pts_improvement DESC
        ) AS points_rank,
        DENSE_RANK() OVER (
            ORDER BY reb_improvement DESC
        ) AS rebounds_rank,
        DENSE_RANK() OVER (
            ORDER BY ast_improvement DESC
        ) AS assists_rank
    FROM improvements
)
SELECT
    category,
    ranking,
    player_name,
    previous_season,
    season,
    previous_value,
    current_value,
    improvement
FROM (
    SELECT
        1 AS category_order,
        'Points' AS category,
        points_rank AS ranking,
        player_name,
        previous_season,
        season,
        CAST(previous_pts AS decimal(5,1)) AS previous_value,
        CAST(pts AS decimal(5,1)) AS current_value,
        CAST(pts_improvement AS decimal(5,1)) AS improvement
    FROM ranked_improvements
    WHERE points_rank <= 5

    UNION ALL

    SELECT
        2, 'Rebounds', rebounds_rank, player_name,
        previous_season, season,
        CAST(previous_reb AS decimal(5,1)),
        CAST(reb AS decimal(5,1)),
        CAST(reb_improvement AS decimal(5,1))
    FROM ranked_improvements
    WHERE rebounds_rank <= 5

    UNION ALL

    SELECT
        3, 'Assists', assists_rank, player_name,
        previous_season, season,
        CAST(previous_ast AS decimal(5,1)),
        CAST(ast AS decimal(5,1)),
        CAST(ast_improvement AS decimal(5,1))
    FROM ranked_improvements
    WHERE assists_rank <= 5
) AS results
ORDER BY category_order, ranking, player_name;




-- Analysis 4: Player size, style and performance by era

SELECT
    era,
    COUNT(DISTINCT season) AS seasons_covered,
    COUNT(*) AS player_seasons,
    CAST(AVG(player_height) AS decimal(6,2)) AS avg_height_cm,
    CAST(AVG(player_weight) AS decimal(6,2)) AS avg_weight_kg,
    CAST(AVG(age) AS decimal(4,1)) AS avg_age,
    CAST(AVG(pts) AS decimal(5,1)) AS avg_points,
    CAST(AVG(reb) AS decimal(5,1)) AS avg_rebounds,
    CAST(AVG(ast) AS decimal(5,1)) AS avg_assists,
    CAST(AVG(usg_pct_num) * 100 AS decimal(5,1)) AS avg_usage_pct,
    CAST(AVG(ts_pct_num) * 100 AS decimal(5,1)) AS avg_ts_pct
FROM dbo.vw_nba_player_stats_clean
GROUP BY era
ORDER BY MIN(season_start);





-- Analysis 5: Teams producing top-five performers

;WITH ranked_players AS (
    SELECT
        season,
        player_name,
        team_abbreviation,
        DENSE_RANK() OVER (
            PARTITION BY season ORDER BY pts DESC
        ) AS points_rank,
        DENSE_RANK() OVER (
            PARTITION BY season ORDER BY reb DESC
        ) AS rebounds_rank,
        DENSE_RANK() OVER (
            PARTITION BY season ORDER BY ast DESC
        ) AS assists_rank
    FROM dbo.vw_nba_player_stats_clean
    WHERE eligible_calc = 1
),
top_performances AS (
    SELECT
        season,
        player_name,
        team_abbreviation,
        ranking.category
    FROM ranked_players
    CROSS APPLY (
        VALUES
            ('Scoring', points_rank),
            ('Rebounding', rebounds_rank),
            ('Playmaking', assists_rank)
    ) AS ranking(category, category_rank)
    WHERE ranking.category_rank <= 5
)
SELECT TOP 10
    team_abbreviation,
    COUNT(*) AS top_five_appearances,
    COUNT(DISTINCT season) AS seasons_with_top_performer,
    COUNT(DISTINCT player_name) AS different_top_players,
    SUM(CASE WHEN category = 'Scoring' THEN 1 ELSE 0 END)
        AS scoring_appearances,
    SUM(CASE WHEN category = 'Rebounding' THEN 1 ELSE 0 END)
        AS rebounding_appearances,
    SUM(CASE WHEN category = 'Playmaking' THEN 1 ELSE 0 END)
        AS playmaking_appearances
FROM top_performances
GROUP BY team_abbreviation
ORDER BY top_five_appearances DESC, seasons_with_top_performer DESC;




-- Analysis 6: Rookie versus veteran contributions

SELECT
    career_stage,
    COUNT(*) AS eligible_player_seasons,
    CAST(AVG(age) AS decimal(4,1)) AS avg_age,
    CAST(AVG(gp) AS decimal(5,1)) AS avg_games,
    CAST(AVG(pts) AS decimal(5,1)) AS avg_points,
    CAST(AVG(reb) AS decimal(5,1)) AS avg_rebounds,
    CAST(AVG(ast) AS decimal(5,1)) AS avg_assists,
    CAST(AVG(usg_pct_num) * 100 AS decimal(5,1)) AS avg_usage_pct,
    CAST(AVG(ts_pct_num) * 100 AS decimal(5,1)) AS avg_ts_pct,
    CAST(AVG(net_rating) AS decimal(6,1)) AS avg_net_rating
FROM dbo.vw_nba_player_stats_clean
WHERE eligible_calc = 1
  AND career_stage IN ('Rookie', 'Veteran')
GROUP BY career_stage
ORDER BY
    CASE WHEN career_stage = 'Rookie' THEN 1 ELSE 2 END;





    -- Analysis 7: Data MVP for the 2022-23 season

;WITH season_players AS (
    SELECT
        player_name,
        team_abbreviation,
        gp,
        pts,
        reb,
        ast,
        ts_pct_num,
        MIN(pts) OVER () AS min_pts,
        MAX(pts) OVER () AS max_pts,
        MIN(reb) OVER () AS min_reb,
        MAX(reb) OVER () AS max_reb,
        MIN(ast) OVER () AS min_ast,
        MAX(ast) OVER () AS max_ast,
        MIN(ts_pct_num) OVER () AS min_ts,
        MAX(ts_pct_num) OVER () AS max_ts
    FROM dbo.vw_nba_player_stats_clean
    WHERE season = '2022-23'
      AND eligible_calc = 1
),
normalized_scores AS (
    SELECT *,
        100.0 * (pts - min_pts)
            / NULLIF(max_pts - min_pts, 0) AS points_score,
        100.0 * (reb - min_reb)
            / NULLIF(max_reb - min_reb, 0) AS rebounds_score,
        100.0 * (ast - min_ast)
            / NULLIF(max_ast - min_ast, 0) AS assists_score,
        100.0 * (ts_pct_num - min_ts)
            / NULLIF(max_ts - min_ts, 0) AS efficiency_score
    FROM season_players
),
mvp_scores AS (
    SELECT *,
        0.40 * points_score
        + 0.15 * rebounds_score
        + 0.15 * assists_score
        + 0.30 * efficiency_score AS data_mvp_score
    FROM normalized_scores
)
SELECT TOP 10
    DENSE_RANK() OVER (
        ORDER BY data_mvp_score DESC
    ) AS data_mvp_rank,
    player_name,
    team_abbreviation,
    gp,
    CAST(pts AS decimal(5,1)) AS pts,
    CAST(reb AS decimal(5,1)) AS reb,
    CAST(ast AS decimal(5,1)) AS ast,
    CAST(ts_pct_num * 100 AS decimal(5,1)) AS ts_pct,
    CAST(data_mvp_score AS decimal(6,2)) AS data_mvp_score
FROM mvp_scores
ORDER BY data_mvp_score DESC;





-- Analysis 8: Highest Data MVP scores across all seasons

;WITH season_players AS (
    SELECT
        season,
        player_name,
        team_abbreviation,
        gp,
        pts,
        reb,
        ast,
        ts_pct_num,
        MIN(pts) OVER (PARTITION BY season) AS min_pts,
        MAX(pts) OVER (PARTITION BY season) AS max_pts,
        MIN(reb) OVER (PARTITION BY season) AS min_reb,
        MAX(reb) OVER (PARTITION BY season) AS max_reb,
        MIN(ast) OVER (PARTITION BY season) AS min_ast,
        MAX(ast) OVER (PARTITION BY season) AS max_ast,
        MIN(ts_pct_num) OVER (PARTITION BY season) AS min_ts,
        MAX(ts_pct_num) OVER (PARTITION BY season) AS max_ts
    FROM dbo.vw_nba_player_stats_clean
    WHERE eligible_calc = 1
),
normalized_scores AS (
    SELECT *,
        100.0 * (pts - min_pts)
            / NULLIF(max_pts - min_pts, 0) AS points_score,
        100.0 * (reb - min_reb)
            / NULLIF(max_reb - min_reb, 0) AS rebounds_score,
        100.0 * (ast - min_ast)
            / NULLIF(max_ast - min_ast, 0) AS assists_score,
        100.0 * (ts_pct_num - min_ts)
            / NULLIF(max_ts - min_ts, 0) AS efficiency_score
    FROM season_players
),
mvp_scores AS (
    SELECT *,
        0.40 * points_score
        + 0.15 * rebounds_score
        + 0.15 * assists_score
        + 0.30 * efficiency_score AS data_mvp_score
    FROM normalized_scores
)
SELECT TOP 20
    ROW_NUMBER() OVER (
        ORDER BY data_mvp_score DESC
    ) AS overall_rank,
    season,
    player_name,
    team_abbreviation,
    CAST(pts AS decimal(5,1)) AS pts,
    CAST(reb AS decimal(5,1)) AS reb,
    CAST(ast AS decimal(5,1)) AS ast,
    CAST(ts_pct_num * 100 AS decimal(5,1)) AS ts_pct,
    CAST(data_mvp_score AS decimal(6,2)) AS data_mvp_score
FROM mvp_scores
ORDER BY data_mvp_score DESC;






-- Position lookup for leading Dream Team candidates

CREATE TABLE dbo.player_position_lookup (
    player_name nvarchar(50) PRIMARY KEY,
    primary_position varchar(2) NOT NULL
);

INSERT INTO dbo.player_position_lookup
    (player_name, primary_position)
VALUES
    ('Stephen Curry', 'PG'),
    ('Russell Westbrook', 'PG'),
    ('James Harden', 'SG'),
    ('Tracy McGrady', 'SG'),
    ('LeBron James', 'SF'),
    ('Kevin Durant', 'SF'),
    ('Karl Malone', 'PF'),
    ('Shaquille O''Neal', 'C'),
    ('Nikola Jokic', 'C'),
    ('Joel Embiid', 'C');










    GO

CREATE OR ALTER VIEW dbo.vw_data_mvp_scores AS
WITH season_players AS (
    SELECT
        season,
        player_name,
        team_abbreviation,
        gp,
        pts,
        reb,
        ast,
        ts_pct_num,
        MIN(pts) OVER (PARTITION BY season) AS min_pts,
        MAX(pts) OVER (PARTITION BY season) AS max_pts,
        MIN(reb) OVER (PARTITION BY season) AS min_reb,
        MAX(reb) OVER (PARTITION BY season) AS max_reb,
        MIN(ast) OVER (PARTITION BY season) AS min_ast,
        MAX(ast) OVER (PARTITION BY season) AS max_ast,
        MIN(ts_pct_num) OVER (PARTITION BY season) AS min_ts,
        MAX(ts_pct_num) OVER (PARTITION BY season) AS max_ts
    FROM dbo.vw_nba_player_stats_clean
    WHERE eligible_calc = 1
),
normalized_scores AS (
    SELECT *,
        100.0 * (pts - min_pts)
            / NULLIF(max_pts - min_pts, 0) AS points_score,
        100.0 * (reb - min_reb)
            / NULLIF(max_reb - min_reb, 0) AS rebounds_score,
        100.0 * (ast - min_ast)
            / NULLIF(max_ast - min_ast, 0) AS assists_score,
        100.0 * (ts_pct_num - min_ts)
            / NULLIF(max_ts - min_ts, 0) AS efficiency_score
    FROM season_players
)
SELECT
    season,
    player_name,
    team_abbreviation,
    gp,
    pts,
    reb,
    ast,
    ts_pct_num,
    points_score,
    rebounds_score,
    assists_score,
    efficiency_score,
    0.40 * points_score
    + 0.15 * rebounds_score
    + 0.15 * assists_score
    + 0.30 * efficiency_score AS data_mvp_score
FROM normalized_scores;

GO

;WITH position_rankings AS (
    SELECT
        p.primary_position,
        m.*,
        ROW_NUMBER() OVER (
            PARTITION BY p.primary_position
            ORDER BY m.data_mvp_score DESC
        ) AS position_rank
    FROM dbo.vw_data_mvp_scores AS m
    INNER JOIN dbo.player_position_lookup AS p
        ON m.player_name = p.player_name
)
SELECT
    primary_position AS position,
    player_name,
    season,
    team_abbreviation,
    CAST(pts AS decimal(5,1)) AS pts,
    CAST(reb AS decimal(5,1)) AS reb,
    CAST(ast AS decimal(5,1)) AS ast,
    CAST(ts_pct_num * 100 AS decimal(5,1)) AS ts_pct,
    CAST(data_mvp_score AS decimal(6,2)) AS data_mvp_score
FROM position_rankings
WHERE position_rank = 1
ORDER BY
    CASE primary_position
        WHEN 'PG' THEN 1
        WHEN 'SG' THEN 2
        WHEN 'SF' THEN 3
        WHEN 'PF' THEN 4
        WHEN 'C' THEN 5
    END;