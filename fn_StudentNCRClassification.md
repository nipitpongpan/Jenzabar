# fn_StudentNCRClassification

## Overview

The `fn_StudentNCRClassification` SQL function classifies students into three categories:
- **New (N):** Students who have no prior enrollment history.
- **Continue (C):** Students who were enrolled in the immediate prior term(s).
- **Return (R):** Students who were enrolled in a past term but not in the immediate prior term(s).

This function simplifies the process of categorizing students based on their enrollment records, which is useful for generating reports, dashboards, and institutional analytics.

---

## Function Logic

### Inputs
The function takes the following parameters:
- **`@year_code`** (`CHAR(4)`): The academic year code (e.g., `'2425'` for 2024-2025).
- **`@term_code`** (`CHAR(2)`): The term code (e.g., `'FA'` for Fall, `'SP'` for Spring, `'SU'` for Summer).
- **`@id_num`** (`INT`): The unique identifier for the student.

### Outputs
The function returns a single character:
- `'N'` for New.
- `'C'` for Continue.
- `'R'` for Return.

### Classification Logic

1. **New (`N`)**:
   - The student has no valid enrollment history in `student_crs_hist`.

2. **Continue (`C`)**:
   - The student was enrolled in the **immediate prior term(s)**:
     - **Fall (`FA`)**: Spring and Summer of the previous academic year.
     - **Spring (`SP`)**: Fall of the previous academic year.
     - **Summer (`SU`)**: Spring of the same academic year.

3. **Return (`R`)**:
   - The student has valid enrollment records in `student_crs_hist` but **skipped the immediate prior term(s)**.


---

## SQL Function Definition

```sql
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
```


---

## Dependencies

### Tables
1. **`year_term_table`**:
   - Stores term metadata.
   - Columns:
     - `yr_cde` (`CHAR(4)`): Academic year code.
     - `trm_cde` (`CHAR(2)`): Term code.
     - `trm_begin_dte` (`DATE`): Term start date.
     - `trm_end_dte` (`DATE`): Term end date.

2. **`student_crs_hist`**:
   - Stores student enrollment history.
   - Columns:
     - `id_num` (`INT`): Student ID.
     - `yr_cde` (`CHAR(4)`): Academic year code.
     - `trm_cde` (`CHAR(2)`): Term code.
     - `transaction_sts` (`CHAR(1)`): Enrollment status (`'A'` for active, `'D'` for dropped).
     - `grade_cde` (`CHAR(2)`): Grade code (e.g., `'A'`, `'B'`, `'nw'`).
     - `credit_hrs` (`DECIMAL`): Credit hours enrolled.

---

## Example Usage

### Input
To classify a student with ID `12345` for the Fall 2024 term:
```sql
SELECT dbo.fn_StudentNCRClassification('2425', 'FA', 12345) AS Classification;
```

### Output
The function returns:
- `'N'`: The student has no prior enrollment history.
- `'C'`: The student was enrolled in the prior term(s).
- `'R'`: The student was enrolled in a past term but not the immediate prior term(s).

---

## Test Cases

### Sample Data
#### `year_term_table`
| yr_cde | trm_cde | trm_begin_dte | trm_end_dte |
|--------|---------|---------------|-------------|
| 2425   | FA      | 2024-08-15    | 2024-12-15  |
| 2425   | SP      | 2025-01-15    | 2025-05-15  |
| 2425   | SU      | 2025-06-01    | 2025-07-31  |

#### `student_crs_hist`
| id_num | yr_cde | trm_cde | transaction_sts | grade_cde | credit_hrs |
|--------|--------|---------|-----------------|-----------|------------|
| 12345  | 2425   | SP      | A               | A         | 3.0        |
| 12345  | 2425   | FA      | A               | B         | 3.0        |

### Tests
1. **New Student**:
   - Input: `fn_StudentNCRClassification('2425', 'FA', 54321)`
   - Output: `'N'`

2. **Continuing Student**:
   - Input: `fn_StudentNCRClassification('2425', 'FA', 12345)`
   - Output: `'C'`

3. **Returning Student**:
   - Input: `fn_StudentNCRClassification('2425', 'SP', 12345)`
   - Output: `'R'`

---


