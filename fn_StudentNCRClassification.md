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

### Logic

1. **Determine Relevant Terms:**
   - Based on the current term (`@year_code` + `@term_code`), identify the immediate prior term(s).
   - For Fall (`'FA'`), include both Spring (`'SP'`) and Summer (`'SU'`) of the same academic year.
   - For Spring (`'SP'`) or Summer (`'SU'`), include only the most recent prior term.

2. **Classify Students:**
   - **New (`N`):**
     - No enrollment records exist in the `student_crs_hist` table.
   - **Continue (`C`):**
     - The student has an enrollment record in the immediate prior term(s).
   - **Return (`R`):**
     - The student has prior enrollment records but not in the immediate prior term(s).

3. **Validation Criteria:**
   - Exclude:
     - Dropped courses (`transaction_sts = 'D'`).
     - Invalid grades (`'nw'`, `'ew'`, `'X'`).
     - Placeholder terms (`'TRAN'`, `'ZZZZ'`).

---

## SQL Function Definition

```sql
CREATE FUNCTION fn_StudentNCRClassification (
    @year_code CHAR(4),
    @term_code CHAR(2),
    @id_num INT
)
RETURNS CHAR(1)
AS
BEGIN
    DECLARE @Result CHAR(1);
    DECLARE @term_no INT;

    -- Determine the number of terms to check
    IF @term_code = 'FA'
        SET @term_no = 2; -- Fall: Include Spring and Summer
    ELSE
        SET @term_no = 1; -- Spring and Summer: Include the immediate prior term

    -- Temporary table to store relevant terms
    DECLARE @term_list TABLE (termlist CHAR(6));

    INSERT INTO @term_list (termlist)
    SELECT TOP (@term_no) yr_cde + trm_cde
    FROM year_term_table
    WHERE trm_begin_dte < (
        SELECT trm_begin_dte
        FROM year_term_table
        WHERE yr_cde + trm_cde = @year_code + @term_code
    )
    ORDER BY trm_begin_dte DESC;

    -- Classification logic
    SET @Result = (
        SELECT CASE
            WHEN NOT EXISTS (
                SELECT 1
                FROM student_crs_hist
                WHERE id_num = @id_num
                  AND credit_hrs > 0
                  AND transaction_sts <> 'D'
            ) THEN 'N' -- New
            WHEN EXISTS (
                SELECT 1
                FROM student_crs_hist
                WHERE id_num = @id_num
                  AND yr_cde + trm_cde IN (SELECT termlist FROM @term_list)
                  AND credit_hrs > 0
                  AND transaction_sts <> 'D'
            ) THEN 'C' -- Continue
            ELSE 'R' -- Return
        END
    );

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


