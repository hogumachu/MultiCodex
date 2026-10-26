-- Schema-only fixture from installed Codex, 2026-10-26. Contains no user records.
CREATE TABLE _sqlx_migrations (
    version BIGINT PRIMARY KEY,
    description TEXT NOT NULL,
    installed_on TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    success BOOLEAN NOT NULL,
    checksum BLOB NOT NULL,
    execution_time BIGINT NOT NULL
);
CREATE TABLE thread_turns (
    thread_id TEXT NOT NULL,
    turn_id TEXT NOT NULL,
    rollout_ordinal INTEGER NOT NULL,
    status TEXT NOT NULL,
    error_json TEXT,
    started_at INTEGER,
    completed_at INTEGER,
    duration_ms INTEGER,
    first_user_item_id TEXT,
    final_agent_item_id TEXT, rollout_byte_offset INTEGER, rollout_end_ordinal INTEGER, rollout_end_byte_offset INTEGER, root_turn_id TEXT,
    PRIMARY KEY (thread_id, turn_id)
);
CREATE TABLE thread_items (
    thread_id TEXT NOT NULL,
    turn_id TEXT NOT NULL,
    item_id TEXT NOT NULL,
    rollout_ordinal INTEGER NOT NULL,
    created_at_ms INTEGER NOT NULL,
    item_json TEXT NOT NULL, item_type TEXT NOT NULL DEFAULT '', updated_at_ordinal INTEGER NOT NULL DEFAULT 0, started_at_ms INTEGER, completed_at_ms INTEGER,
    PRIMARY KEY (thread_id, turn_id, item_id)
);
CREATE TABLE thread_history_projection_state (
    thread_id TEXT PRIMARY KEY,
    next_rollout_byte_offset INTEGER NOT NULL,
    next_rollout_ordinal INTEGER NOT NULL
);
CREATE TABLE thread_realtime_items (
    thread_id TEXT NOT NULL,
    item_id TEXT NOT NULL,
    rollout_ordinal INTEGER NOT NULL,
    created_at_ms INTEGER NOT NULL,
    item_type TEXT NOT NULL,
    item_json TEXT NOT NULL,
    PRIMARY KEY (thread_id, item_id)
);
CREATE UNIQUE INDEX idx_thread_turns_page
    ON thread_turns(thread_id, rollout_ordinal);
CREATE UNIQUE INDEX idx_thread_items_page
    ON thread_items(thread_id, rollout_ordinal);
CREATE INDEX idx_thread_items_by_turn_page
    ON thread_items(thread_id, turn_id, rollout_ordinal);
CREATE INDEX idx_thread_items_user_messages
    ON thread_items(thread_id, rollout_ordinal)
    WHERE item_type = 'userMessage';
CREATE INDEX idx_thread_items_updated_page
    ON thread_items(thread_id, updated_at_ordinal);
CREATE INDEX idx_thread_items_by_turn_updated_page
    ON thread_items(thread_id, turn_id, updated_at_ordinal);
CREATE UNIQUE INDEX idx_thread_realtime_items_page
    ON thread_realtime_items(thread_id, rollout_ordinal);
CREATE INDEX idx_thread_realtime_items_boundary
    ON thread_realtime_items(thread_id, rollout_ordinal)
    WHERE item_type IN ('realtime_session_started', 'realtime_session_closed');
CREATE INDEX idx_thread_turns_end_page
    ON thread_turns(thread_id, rollout_end_ordinal, turn_id)
    WHERE rollout_end_ordinal IS NOT NULL;
CREATE TRIGGER thread_realtime_items_projection_cleanup
    AFTER DELETE ON thread_history_projection_state
BEGIN
    DELETE FROM thread_realtime_items WHERE thread_id = OLD.thread_id;
END;
INSERT INTO _sqlx_migrations (version,description,success,checksum,execution_time) VALUES (1,'fixture',1,X'2AD9A4AB17DF511FB73F03337133DE94A172DC0A1F5729B5EF61FE106DB03D1A43BDB5978B0CB7D7BC74071D3CA34A92',0);
INSERT INTO _sqlx_migrations (version,description,success,checksum,execution_time) VALUES (2,'fixture',1,X'AE61DBC1A6422530AA93914DBCAC363A0238B86AE1A9D77EB041C75330E1283A0FCF93A043DEEEFCD6FD2C4037694BC4',0);
INSERT INTO _sqlx_migrations (version,description,success,checksum,execution_time) VALUES (3,'fixture',1,X'A51DA2A11DF7760D8F8CAB221E82B36CE8C0A30F16D44F3602E7F0FBC622CA72F1C3E3ECF22A194E12C2222BDCB51AFE',0);
INSERT INTO _sqlx_migrations (version,description,success,checksum,execution_time) VALUES (4,'fixture',1,X'65F33B171BD3AAFE9D24728B2CA6A5C720A3AB54AED472998F8ACF7489F0D35B2DFD12258A2D17BE993BF17098B5E50C',0);
INSERT INTO _sqlx_migrations (version,description,success,checksum,execution_time) VALUES (5,'fixture',1,X'2FDAD8E361DC1F828AFACF10BD2EB1F511B02DEEF7FA234A9C412D0211DE126D1CFAD54B175C9C3A9731548F9084B437',0);
INSERT INTO _sqlx_migrations (version,description,success,checksum,execution_time) VALUES (6,'fixture',1,X'02ED82D375ADB58B5C0C09E0154F3331D507CEA7AF446D12324E5653CDBA9A91F84AFD38CF2A29F33030614689DEB9DE',0);
INSERT INTO _sqlx_migrations (version,description,success,checksum,execution_time) VALUES (7,'fixture',1,X'9334ADB4CDA792116A47B69A19E3840AE3806B08773EF1794043FE0AA72891360ACB1A0A8431084D53C568482C5FDD20',0);
INSERT INTO _sqlx_migrations (version,description,success,checksum,execution_time) VALUES (8,'fixture',1,X'94635CD58535ADB1679F4AD07A9D14231B69004405FA88A22DB1B6A7E5FEAC8B6B66AD97EA16FCE464B99BFF5B3548D3',0);
