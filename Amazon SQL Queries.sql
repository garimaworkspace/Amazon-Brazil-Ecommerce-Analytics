SELECT * FROM amazon.product_category_name_translation;

-- Q1. Find the total number of orders fulfilled by each seller state. 

/* Amazon Brazil's logistics team is planning its next round of 
regional fulfillment center investments. Before committing budget, they need to know which 
states are generating the most order volume on the seller side 
— so infrastructure goes where the actual demand is. */

SELECT
    s.seller_state,
    COUNT(DISTINCT oi.order_id) AS total_orders
FROM sellers AS s
JOIN order_items AS oi
    ON s.seller_id = oi.seller_id
GROUP BY s.seller_state
ORDER BY total_orders DESC;

-- Q2. For each product category, calculate the cumulative revenue generated as orders come in over time. 

/*The growth team wants to see how revenue builds up within each category across the order timeline. 
This running total helps them spot which categories hit their revenue targets early in the month 
versus which ones pick up only toward the end — useful for planning flash sales and push notifications. */

SELECT
    pct.product_category_name_english AS product_category,
    DATE(o.order_purchase_timestamp) AS order_date,
    SUM(oi.price) AS daily_revenue,
    SUM(SUM(oi.price)) OVER (
        PARTITION BY pct.product_category_name_english
        ORDER BY DATE(o.order_purchase_timestamp)
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS cumulative_revenue
FROM orders AS o
INNER JOIN order_items AS oi
    ON o.order_id = oi.order_id
INNER JOIN products AS p
    ON oi.product_id = p.product_id
LEFT JOIN product_category_name_translation AS pct
    ON p.product_category_name = pct.product_category_name
WHERE o.order_purchase_timestamp IS NOT NULL
GROUP BY
    pct.product_category_name_english,
    DATE(o.order_purchase_timestamp)
ORDER BY
    product_category,
    order_date;
    
    
    
-- Q3. Which payment method do customers use the most, and what is the average order value for each payment type? 

/*The finance and partnerships team is renegotiating contracts with payment providers. 
Before those talks, they need to know which payment method — credit card, boleto, voucher, or debit card — dominates the platform, 
and whether high-value orders cluster around a specific payment type. */

SELECT
    op.payment_type,
    COUNT(DISTINCT op.order_id) AS total_orders,
    ROUND(AVG(op.order_value), 2) AS avg_order_value
FROM (
    SELECT
        order_id,
        payment_type,
        SUM(payment_value) AS order_value
    FROM order_payments
    GROUP BY
        order_id,
        payment_type
) AS op
GROUP BY
    op.payment_type
ORDER BY
    total_orders DESC;


-- Q4. Find the customer who has spent the most money across all their orders. 

/* The CRM team is launching Amazon Brazil's first premium loyalty tier. The first step is 
identifying the single highest-spending customer on the platform — both to personally onboard them into the 
program and to understand what a top-tier customer profile looks like. */


SELECT
    c.customer_unique_id,
    ROUND(SUM(op.payment_value), 2) AS total_spent
FROM customers AS c
INNER JOIN orders AS o
    ON c.customer_id = o.customer_id
INNER JOIN order_payments AS op
    ON o.order_id = op.order_id
GROUP BY
    c.customer_unique_id
ORDER BY
    total_spent DESC
LIMIT 1;


-- Q5. Find the average review score for each product category. 

/* The customer experience team tracks satisfaction at the category level. A low average review score in a category 
often signals a fulfillment issue, a product quality problem, or a mismatch between listing description and actual product.
This query helps them prioritize which categories need intervention first. */



SELECT
    pct.product_category_name_english AS product_category,
    ROUND(AVG(r.review_score), 2) AS average_review_score
FROM order_reviews r
JOIN order_items oi
    ON r.order_id = oi.order_id
JOIN products p
    ON oi.product_id = p.product_id
JOIN product_category_name_translation pct
    ON p.product_category_name = pct.product_category_name
GROUP BY
    pct.product_category_name_english
ORDER BY
    average_review_score ASC;
    

-- Q6. Find the total number of orders placed by each customer, broken down by the state they live in. 

/* The regional marketing team is planning state-level campaigns in Brazil. They want to know how order 
frequency varies by customer location — so they can target low-frequency states with acquisition offers 
and reward high-frequency states with loyalty perks. */


SELECT
    c.customer_unique_id,
    c.customer_state,
    COUNT(DISTINCT o.order_id) AS total_orders
FROM customers c
JOIN orders o
    ON c.customer_id = o.customer_id
GROUP BY
    c.customer_unique_id,
    c.customer_state
ORDER BY
    c.customer_state,
    total_orders DESC;
    

-- Q7. Identify sellers who registered on the platform but have never fulfilled a single order. 

/* The seller growth team runs quarterly re-engagement campaigns targeting dormant sellers. 
To build that list, they need to find every seller account that exists in the system but has zero fulfilled orders — 
these are the accounts that need a nudge or need to be reviewed for removal. */


SELECT
    s.seller_id,
    s.seller_city,
    s.seller_state
FROM sellers s
LEFT JOIN order_items oi
    ON s.seller_id = oi.seller_id
WHERE oi.seller_id IS NULL;



-- Q8. Find the top 5 product categories by total revenue. 

/* Before every major sales event — Black Friday Brazil, Dia das Mães, Cyber Monday — 
the merchandising team decides which categories get homepage real estate and promotional budget. 
Total revenue by category is the primary input for that decision.*/


SELECT
    pct.product_category_name_english AS product_category,
    ROUND(SUM(oi.price), 2) AS total_revenue
FROM order_items oi
JOIN products p
    ON oi.product_id = p.product_id
JOIN product_category_name_translation pct
    ON p.product_category_name = pct.product_category_name
GROUP BY
    pct.product_category_name_english
ORDER BY
    total_revenue DESC
LIMIT 5;


-- Q9. Find the median delivery time (in days) between order placement and actual delivery. 

/* The logistics director wants to know the true middle ground of how long customers wait for their orders. 
The median is preferred over the average here because a handful of extremely delayed orders
 (due to remote delivery locations in Brazil's interior) would skew the average and 
 make performance look worse than it is for most customers. */
 

WITH delivery_times AS (
    SELECT
        DATEDIFF(
            order_delivered_customer_date,
            order_purchase_timestamp
        ) AS delivery_days
    FROM orders
    WHERE order_delivered_customer_date IS NOT NULL
      AND order_purchase_timestamp IS NOT NULL
),
ranked_delivery AS (
    SELECT
        delivery_days,
        ROW_NUMBER() OVER (
            ORDER BY delivery_days
        ) AS row_num,
        COUNT(*) OVER () AS total_rows
    FROM delivery_times
)
SELECT
    AVG(delivery_days) AS median_delivery_days
FROM ranked_delivery
WHERE row_num IN (
    FLOOR((total_rows + 1) / 2),
    FLOOR((total_rows + 2) / 2)
);


-- Q10. Find all products that have never been ordered. 

/* The catalogue operations team does a quarterly clean-up of dead listings. Products that have never received a single order
 waste search index space, confuse customers, and inflate category browse pages. 
 This query gives them the exact list to review, reprice, or remove. */

SELECT
    p.product_id,
    p.product_category_name
FROM products p
LEFT JOIN order_items oi
    ON p.product_id = oi.product_id
WHERE oi.product_id IS NULL;

-- Q11. Find sellers who have fulfilled more orders than the average seller on the platform. 

/* The seller success team is building an invite list for Amazon Brazil's "Top Seller" badge program. 
Only sellers who perform above the platform average qualify. This query identifies exactly who clears 
that bar — and gives the team a baseline for what above-average performance actually means numerically. */


WITH seller_orders AS (
    SELECT
        s.seller_id,
        COUNT(DISTINCT oi.order_id) AS total_orders
    FROM sellers s
    LEFT JOIN order_items oi
        ON s.seller_id = oi.seller_id
    GROUP BY s.seller_id
)
SELECT
    seller_id,
    total_orders
FROM seller_orders
WHERE total_orders > (
    SELECT AVG(total_orders)
    FROM seller_orders
)
ORDER BY total_orders DESC;

-- Q12. Find which Brazilian states have the highest average customer review score for orders delivered there. 

/* The last-mile delivery experience varies significantly across Brazil — deliveries to São Paulo and Rio are generally faster 
and smoother than to states in the North and Northeast. This query helps the CX team correlate delivery destination 
with satisfaction, so they can push logistics partners to improve in underperforming states. */

SELECT
    c.customer_state,
    ROUND(AVG(r.review_score), 2) AS average_review_score,
    COUNT(DISTINCT o.order_id) AS total_delivered_orders
FROM customers c
JOIN orders o
    ON c.customer_id = o.customer_id
JOIN order_reviews r
    ON o.order_id = r.order_id
WHERE o.order_status = 'delivered'
  AND o.order_delivered_customer_date IS NOT NULL
GROUP BY c.customer_state
ORDER BY average_review_score DESC;

-- Q13. Identify customers who have placed orders but never left a review. 

/* The post-purchase engagement team wants to grow the volume of reviews on the platform — more 
reviews mean better product discoverability and buyer trust. The first step is identifying 
customers who buy regularly but never review, so the team can target them with review reminder emails 
and in-app nudges. */

SELECT
    c.customer_unique_id,
    c.customer_city,
    c.customer_state,
    COUNT(DISTINCT o.order_id) AS total_orders
FROM customers c
JOIN orders o
    ON c.customer_id = o.customer_id
LEFT JOIN order_reviews r
    ON o.order_id = r.order_id
GROUP BY
    c.customer_unique_id,
    c.customer_city,
    c.customer_state
HAVING COUNT(DISTINCT r.order_id) = 0
ORDER BY total_orders DESC;

-- Q14. Find the month with the highest number of orders placed across the entire platform. 

/* The demand forecasting team needs to know Amazon Brazil's peak order month historically.
 This drives decisions about how much warehouse capacity to reserve, how many temporary delivery staff to hire, 
 and when to start marketing campaigns for the next peak season. */
 

SELECT
    MONTHNAME(order_purchase_timestamp) AS order_month,
    COUNT(order_id) AS total_orders
FROM orders
GROUP BY
    MONTH(order_purchase_timestamp),
    MONTHNAME(order_purchase_timestamp)
ORDER BY total_orders DESC
LIMIT 1;

















