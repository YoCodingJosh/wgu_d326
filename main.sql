-- Part B
CREATE OR REPLACE FUNCTION determine_rental_status(return_date_param TIMESTAMP)
RETURNS VARCHAR AS $$
BEGIN
    RETURN CASE 
        WHEN return_date_param IS NOT NULL THEN 'Yes'
        WHEN return_date_param IS NULL THEN 'No'
        ELSE 'Unknown'
    END;
END;
$$ LANGUAGE plpgsql;

-- Test function
SELECT determine_rental_status('2021-01-01');
SELECT determine_rental_status(NULL);

-- Part C
-- Detailed Table
CREATE TABLE rental_details (
    rental_id INT PRIMARY KEY,
    customer_id INT,
    film_title VARCHAR(100),
    rental_date DATE,
    return_date DATE,
    rental_status VARCHAR(10),
    rental_amount DECIMAL(5,2)
);

-- Summary Table
CREATE TABLE rental_summary (
    category_name VARCHAR(50) PRIMARY KEY,
    total_rentals INT,
    total_revenue DECIMAL(10,2),
    avg_rental_duration DECIMAL(5,2)
);

-- Test tables
SELECT * FROM rental_details;
SELECT * FROM rental_summary;

-- Part D
SELECT 
    r.rental_id,
    r.customer_id,
    f.title AS film_title,
    r.rental_date,
    r.return_date,
    determine_rental_status(r.return_date) AS rental_status,
    p.amount AS rental_amount
FROM rental r
JOIN inventory i ON r.inventory_id = i.inventory_id
JOIN film f ON i.film_id = f.film_id
JOIN film_category fc ON f.film_id = fc.film_id
JOIN category c ON fc.category_id = c.category_id
JOIN payment p ON r.rental_id = p.rental_id;

-- Part E
CREATE OR REPLACE FUNCTION update_summary_table()
RETURNS TRIGGER AS $$
BEGIN
    -- Recalculate summary stats after insert into detailed table
    INSERT INTO rental_summary (category_name, total_rentals, total_revenue, avg_rental_duration)
    SELECT 
        c.name AS category_name,
        COUNT(*) AS total_rentals,
        SUM(rd.rental_amount) AS total_revenue,
        AVG(CASE
            WHEN rd.return_date IS NOT NULL THEN
            EXTRACT(EPOCH FROM (rd.return_date::timestamp - rd.rental_date::timestamp)) / 86400.0
            ELSE NULL
        END) AS avg_rental_duration

    FROM rental_details rd
    JOIN inventory i ON rd.rental_id = i.inventory_id
    JOIN film f ON i.film_id = f.film_id
    JOIN film_category fc ON f.film_id = fc.film_id
    JOIN category c ON fc.category_id = c.category_id
    GROUP BY c.name
    ON CONFLICT (category_name) DO UPDATE
    SET 
        total_rentals = EXCLUDED.total_rentals,
        total_revenue = EXCLUDED.total_revenue,
        avg_rental_duration = EXCLUDED.avg_rental_duration;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER rental_details_trigger
AFTER INSERT ON rental_details
FOR EACH STATEMENT
EXECUTE FUNCTION update_summary_table();

-- Part F
CREATE OR REPLACE PROCEDURE refresh_rental_report()
LANGUAGE plpgsql AS $$
BEGIN
    -- Clear tables
    TRUNCATE TABLE rental_details;
    TRUNCATE TABLE rental_summary;
    
    -- Repopulate detailed table
    INSERT INTO rental_details (
        rental_id,
        customer_id,
        film_title,
        rental_date,
        return_date,
        rental_status,
        rental_amount
    )
    SELECT
        r.rental_id,
        r.customer_id,
        f.title AS film_title,
        r.rental_date,
        r.return_date,
        determine_rental_status(r.return_date) AS rental_status,
        -- Sum all payments for that rental
        SUM(p.amount) AS rental_amount
    FROM rental r
    JOIN inventory i      ON r.inventory_id = i.inventory_id
    JOIN film f           ON i.film_id      = f.film_id
    JOIN film_category fc ON f.film_id      = fc.film_id
    JOIN category c       ON fc.category_id = c.category_id
    JOIN payment p        ON r.rental_id    = p.rental_id
    GROUP BY 
        r.rental_id,
        r.customer_id,
        f.title,
        r.rental_date,
        r.return_date;
    
    -- Trigger will automatically update summary table
END;
$$;

-- Test the procedure
CALL refresh_rental_report();
