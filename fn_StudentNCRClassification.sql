SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- =============================================
-- Author:       Nipit Pongpan
-- Create date:  11/23/2024
-- Description:  Classifies students as New (N),
--               Continue (C), or Return (R)
--               based on enrollment history and term logic.
-- =============================================
CREATE FUNCTION [dbo].[fn_StudentNCRClassification]
(
    @year_code CHAR(4),  -- The academic year code (e.g., '2425' for 2024-2025)
    @term_code CHAR(2),  -- The term code (e.g., 'FA' for Fall, 'SP' for Spring, 'SU' for Summer)
    @id_num INT          -- The student ID number
)
RETURNS CHAR(1)
AS
BEGIN
    -- Declare the return variable
    DECLARE @Result CHAR(1);

    -- Declare a variable to determine how many terms to look back
    DECLARE @term_no INT;

    -- Determine the number of preceding terms to include based on the current term
    IF @term_code = 'FA'  
        SET @term_no = 2; -- Fall: Include Spring and Summer
    ELSE 
        SET @term_no = 1; -- Spring and Summer: Include the most recent term

    -- Declare a table to hold the relevant prior terms for comparison
    DECLARE @term_list TABLE (termlist CHAR(6));

    -- Populate the @term_list with preceding terms
    INSERT INTO @term_list (termlist)
    SELECT TOP (@term_no) yr_cde + trm_cde  -- Combine year and term code
    FROM year_term_table
    WHERE trm_begin_dte < (
        -- Select the beginning date of the current term
        SELECT trm_begin_dte
        FROM year_term_table
        WHERE yr_cde + trm_cde = @year_code + @term_code
    )
    ORDER BY trm_begin_dte DESC; -- Get the most recent terms first

    -- Determine the student's classification
    SET @Result = (
        SELECT CASE
            -- Continue: Enrolled in the immediate prior terms with valid grades
            WHEN EXISTS (
                SELECT id_num
                FROM student_crs_hist
                WHERE yr_cde + trm_cde IN (SELECT termlist FROM @term_list)
                  AND transaction_sts <> 'D' -- Exclude dropped courses
                  AND (grade_cde NOT IN ('nw', 'ew', 'X') OR grade_cde IS NULL) -- Exclude invalid grades
                  AND yr_cde NOT IN ('TRAN', 'ZZZZ') -- Exclude transfer or placeholder terms
                  AND id_num = @id_num
                  AND credit_hrs > 0 -- Ensure credit hours are non-zero
            ) THEN 'C'

            -- Return: Enrolled in a past term (not immediate prior) with valid grades
            WHEN EXISTS (
                SELECT id_num
                FROM student_crs_hist
                WHERE yr_cde + trm_cde IN (
                    -- List all terms prior to the most recent in @term_list
                    SELECT yr_cde + trm_cde
                    FROM year_term_table
                    WHERE trm_end_dte < (
                        SELECT TOP 1 trm_begin_dte
                        FROM year_term_table
                        WHERE yr_cde + trm_cde IN (SELECT termlist FROM @term_list)
                        ORDER BY trm_begin_dte
                    )
                )
                  AND transaction_sts <> 'D' -- Exclude dropped courses
                  AND grade_cde NOT IN ('nw', 'ew', 'X', 't', 'tu', 'sw') -- Exclude invalid grades
                  AND yr_cde NOT IN ('TRAN', 'ZZZZ') -- Exclude transfer or placeholder terms
                  AND id_num = @id_num
                  AND credit_hrs > 0 -- Ensure credit hours are non-zero
            ) THEN 'R'

            -- New: No enrollment history exists
            ELSE 'N'
        END
    );

    -- Return the classification
    RETURN @Result;
END;
GO
