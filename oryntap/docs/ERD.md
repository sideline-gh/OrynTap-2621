# OrynTap — Entity-Relationship Diagram

GitHub renders this diagram automatically. To export a picture for the report, paste the code block into <https://mermaid.live> and download PNG/SVG.

```mermaid
erDiagram
    UNIVERSITIES ||--o{ EMAIL_DOMAINS : "accepts"
    UNIVERSITIES ||--o{ PROFILES : "has members"
    UNIVERSITIES ||--o{ STUDY_SPACES : "owns"
    AUTH_USERS ||--|| PROFILES : "1 account = 1 profile"
    STUDY_SPACES ||--o{ OPENING_HOURS : "is open"
    PROFILES ||--o{ CHECK_INS : "makes"
    STUDY_SPACES ||--o{ CHECK_INS : "receives"
    PROFILES ||--o{ FAVOURITES : "saves"
    STUDY_SPACES ||--o{ FAVOURITES : "is saved in"
    STUDY_SPACES ||--o| SPACE_ACTIVITY : "last change"

    UNIVERSITIES {
        smallint id PK
        varchar code UK "AITU, NU, MNU, ENU"
        varchar name UK
        varchar city
        varchar address
        text map_image_url
        text map_embed_url "interactive map (iframe)"
        timestamptz created_at
    }
    EMAIL_DOMAINS {
        varchar domain PK "e.g. astanait.edu.kz"
        smallint university_id FK
    }
    AUTH_USERS {
        uuid id PK
        varchar email UK
        varchar encrypted_password "bcrypt hash"
    }
    PROFILES {
        uuid id PK, FK "= auth.users.id"
        varchar first_name
        varchar last_name
        smallint university_id FK
        varchar role "student | admin"
        timestamptz created_at
    }
    STUDY_SPACES {
        int id PK
        smallint university_id FK
        varchar name "UNIQUE per university"
        varchar kind "library | coworking | atrium | rooms | lounge | cafe"
        varchar building
        varchar floor
        text description
        text image_url
        varchar image_credit "photo source"
        int seat_capacity "CHECK 1..2000"
        int outlet_capacity "CHECK 0..5000"
        boolean counts_exact "false = shown with ~"
        boolean is_quiet
        boolean group_work
        boolean food_allowed
        numeric map_x
        numeric map_y
        boolean is_active
        timestamptz updated_at
    }
    OPENING_HOURS {
        int space_id PK, FK
        smallint weekday PK "1 = Mon ... 7 = Sun"
        time opens
        time closes "CHECK closes > opens"
    }
    CHECK_INS {
        bigint id PK
        uuid user_id FK
        int space_id FK
        boolean uses_outlet
        timestamptz started_at
        timestamptz expires_at "<= started_at + 3 h"
        timestamptz left_at "NULL = still here"
    }
    FAVOURITES {
        uuid user_id PK, FK
        int space_id PK, FK
        timestamptz created_at
    }
    SPACE_ACTIVITY {
        int space_id PK, FK
        timestamptz last_change
    }
    AUDIT_LOG {
        bigint id PK
        uuid actor
        varchar action "INSERT | UPDATE | DELETE"
        varchar table_name
        text record_id
        jsonb details
        timestamptz created_at
    }
```

**Many-to-many:** `PROFILES ↔ STUDY_SPACES` (a student saves many places, and many students save the same place) is resolved by the linking table **FAVOURITES**, which has a composite primary key `(user_id, space_id)`. `CHECK_INS` also links the two tables, but it is an entity with its own id and timestamps.

## Normalisation example (for Part A2)

**Before (unnormalised check-in sheet, like a Google Form export):**

| check_in | student_email | student_name | university | space | space_seats | opens_mon | closes_mon | … | started | ended |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | 240512@astanait.edu.kz | John Doe | Astana IT University | Library | 250 | 08:00 | 22:00 | … | 14:20 | 16:20 |

* **1NF:** the repeating `opens_mon … closes_sun` columns move to their own table, **OPENING_HOURS (space_id, weekday, opens, closes)**. Every value is now atomic. This removes an **insertion anomaly**: before, you could not record hours for a new weekday without adding columns.
* **2NF:** facts about the student and about the space do not depend on the check-in key, so they move out to **PROFILES** and **STUDY_SPACES**. This removes an **update anomaly**: changing the Library's seat count used to mean editing hundreds of rows.
* **3NF:** `university` depended on the e-mail domain, not directly on the student. That is a transitive dependency, so it moves to **UNIVERSITIES** and **EMAIL_DOMAINS**. This removes a **deletion anomaly**: deleting the last AITU student no longer deletes what we know about AITU.
