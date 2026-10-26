-- Schema-only fixture from installed Codex, 2026-10-26. Contains no user records.
CREATE TABLE _sqlx_migrations (
    version BIGINT PRIMARY KEY,
    description TEXT NOT NULL,
    installed_on TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    success BOOLEAN NOT NULL,
    checksum BLOB NOT NULL,
    execution_time BIGINT NOT NULL
);
CREATE TABLE threads (
    id TEXT PRIMARY KEY,
    rollout_path TEXT NOT NULL,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    source TEXT NOT NULL,
    model_provider TEXT NOT NULL,
    cwd TEXT NOT NULL,
    title TEXT NOT NULL,
    sandbox_policy TEXT NOT NULL,
    approval_mode TEXT NOT NULL,
    tokens_used INTEGER NOT NULL DEFAULT 0,
    has_user_event INTEGER NOT NULL DEFAULT 0,
    archived INTEGER NOT NULL DEFAULT 0,
    archived_at INTEGER,
    git_sha TEXT,
    git_branch TEXT,
    git_origin_url TEXT
, cli_version TEXT NOT NULL DEFAULT '', first_user_message TEXT NOT NULL DEFAULT '', agent_nickname TEXT, agent_role TEXT, memory_mode TEXT NOT NULL DEFAULT 'enabled', model TEXT, reasoning_effort TEXT, agent_path TEXT, created_at_ms INTEGER, updated_at_ms INTEGER, thread_source TEXT, preview TEXT NOT NULL DEFAULT '', recency_at INTEGER NOT NULL DEFAULT 0, recency_at_ms INTEGER NOT NULL DEFAULT 0, history_mode TEXT NOT NULL DEFAULT 'legacy', name TEXT, is_pinned INTEGER NOT NULL DEFAULT 0, thread_section_id TEXT
    REFERENCES thread_sections(id) ON DELETE SET NULL, section_position INTEGER, section_entered_at_ms INTEGER, project_id TEXT
    REFERENCES projects(id) ON DELETE SET NULL, originator TEXT, daybreak_enabled BOOLEAN, creator_user_id TEXT, creator_account_id TEXT);
CREATE TABLE thread_dynamic_tools (
    thread_id TEXT NOT NULL,
    position INTEGER NOT NULL,
    name TEXT NOT NULL,
    description TEXT NOT NULL,
    input_schema TEXT NOT NULL, defer_loading INTEGER NOT NULL DEFAULT 0, namespace TEXT,
    PRIMARY KEY(thread_id, position),
    FOREIGN KEY(thread_id) REFERENCES threads(id) ON DELETE CASCADE
);
CREATE TABLE backfill_state (
    id INTEGER PRIMARY KEY CHECK (id = 1),
    status TEXT NOT NULL,
    last_watermark TEXT,
    last_success_at INTEGER,
    updated_at INTEGER NOT NULL
);
CREATE TABLE thread_spawn_edges (
    parent_thread_id TEXT NOT NULL,
    child_thread_id TEXT NOT NULL PRIMARY KEY,
    status TEXT NOT NULL
);
CREATE TABLE remote_control_enrollments (
    websocket_url TEXT NOT NULL,
    account_id TEXT NOT NULL,
    app_server_client_name TEXT NOT NULL,
    server_id TEXT NOT NULL,
    environment_id TEXT NOT NULL,
    server_name TEXT NOT NULL,
    updated_at INTEGER NOT NULL, remote_control_enabled INTEGER,
    PRIMARY KEY (websocket_url, account_id, app_server_client_name)
);
CREATE TABLE external_agent_config_imports (
    import_id TEXT PRIMARY KEY,
    completed_at_ms INTEGER NOT NULL,
    successes TEXT NOT NULL,
    failures TEXT NOT NULL
, provider_id TEXT);
CREATE TABLE thread_sections (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL
, appearance TEXT);
CREATE TABLE rollout_migration_state (
    migration_id TEXT PRIMARY KEY,
    last_checked_thread_created_at INTEGER,
    last_checked_thread_id TEXT,
    updated_at INTEGER NOT NULL
);
CREATE TABLE rollout_migration_skipped_rollouts (
    migration_id TEXT NOT NULL,
    rollout_path TEXT NOT NULL,
    rollout_size_bytes INTEGER NOT NULL,
    rollout_modified_at_ns INTEGER NOT NULL,
    skip_reason TEXT NOT NULL,
    skipped_at INTEGER NOT NULL,
    PRIMARY KEY (migration_id, rollout_path)
);
CREATE TABLE projects (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    metadata TEXT NOT NULL DEFAULT '{}',
    position INTEGER NOT NULL,
    created_at_ms INTEGER NOT NULL,
    updated_at_ms INTEGER NOT NULL
);
CREATE TABLE project_roots (
    project_id TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    position INTEGER NOT NULL,
    path TEXT NOT NULL,
    PRIMARY KEY (project_id, position)
);
CREATE TABLE project_idempotency_keys (
    key TEXT PRIMARY KEY,
    project_id TEXT NOT NULL,
    created_at_ms INTEGER NOT NULL
);
CREATE TABLE "thread_attachments" (
    id TEXT PRIMARY KEY,
    thread_id TEXT NOT NULL REFERENCES threads(id) ON DELETE CASCADE,
    attachment_type TEXT NOT NULL,
    identity_key TEXT NOT NULL,
    payload TEXT NOT NULL,
    created_at INTEGER NOT NULL,
    UNIQUE (thread_id, attachment_type, identity_key)
);
CREATE TABLE guardian_review_feedback (
    id TEXT PRIMARY KEY NOT NULL,
    thread_id TEXT NOT NULL REFERENCES threads(id) ON DELETE CASCADE,
    record BLOB NOT NULL
);
CREATE TABLE thread_read_receipts (
    thread_id TEXT PRIMARY KEY NOT NULL,
    first_unread_turn TEXT,
    revision TEXT NOT NULL,
    last_published_turn TEXT
);
CREATE INDEX idx_threads_created_at ON threads(created_at DESC, id DESC);
CREATE INDEX idx_threads_updated_at ON threads(updated_at DESC, id DESC);
CREATE INDEX idx_threads_archived ON threads(archived);
CREATE INDEX idx_threads_source ON threads(source);
CREATE INDEX idx_threads_provider ON threads(model_provider);
CREATE INDEX idx_thread_dynamic_tools_thread ON thread_dynamic_tools(thread_id);
CREATE INDEX idx_thread_spawn_edges_parent_status
    ON thread_spawn_edges(parent_thread_id, status);
CREATE INDEX idx_threads_created_at_ms ON threads(created_at_ms DESC, id DESC);
CREATE INDEX idx_threads_updated_at_ms ON threads(updated_at_ms DESC, id DESC);
CREATE INDEX idx_threads_archived_cwd_created_at_ms ON threads(archived, cwd, created_at_ms DESC, id DESC);
CREATE INDEX idx_threads_archived_cwd_updated_at_ms ON threads(archived, cwd, updated_at_ms DESC, id DESC);
CREATE INDEX idx_threads_visible_created_at_ms
    ON threads(archived, created_at_ms DESC)
    WHERE preview <> '';
CREATE INDEX idx_threads_visible_updated_at_ms
    ON threads(archived, updated_at_ms DESC)
    WHERE preview <> '';
CREATE INDEX idx_threads_recency_at_ms
    ON threads(recency_at_ms DESC, id DESC);
CREATE INDEX idx_threads_archived_cwd_recency_at_ms
    ON threads(archived, cwd, recency_at_ms DESC, id DESC);
CREATE INDEX idx_threads_visible_recency_at_ms
    ON threads(archived, recency_at_ms DESC, id DESC)
    WHERE preview <> '';
CREATE INDEX idx_threads_pinned_recency_at_ms
    ON threads(archived, recency_at_ms DESC, id DESC)
    WHERE is_pinned = 1 AND preview <> '';
CREATE INDEX idx_projects_position
    ON projects(position ASC, id ASC);
CREATE INDEX idx_threads_project_id
    ON threads(project_id, archived, created_at_ms DESC, id DESC)
    WHERE project_id IS NOT NULL;
CREATE INDEX idx_threads_section_recency_at_ms
    ON threads(archived, thread_section_id, recency_at_ms DESC, id DESC)
    WHERE thread_section_id IS NOT NULL;
CREATE INDEX idx_threads_section_position
    ON threads(archived, thread_section_id, section_position ASC, id ASC)
    WHERE thread_section_id IS NOT NULL;
CREATE INDEX idx_threads_project_recency
    ON threads(project_id, recency_at_ms DESC)
    WHERE archived = 0 AND project_id IS NOT NULL;
CREATE INDEX idx_thread_attachments_thread_created_id
    ON thread_attachments(thread_id, created_at, id);
CREATE INDEX idx_threads_archive_created_at_ms
    ON threads(archived, created_at_ms DESC, id DESC)
    WHERE archived = 1;
CREATE INDEX idx_threads_archive_updated_at_ms
    ON threads(archived, updated_at_ms DESC, id DESC)
    WHERE archived = 1;
CREATE INDEX idx_threads_archive_recency_at_ms
    ON threads(archived, recency_at_ms DESC, id DESC)
    WHERE archived = 1;
CREATE INDEX idx_thread_attachments_identity_thread
    ON thread_attachments(attachment_type, identity_key, thread_id);
CREATE TRIGGER threads_created_at_ms_after_insert
AFTER INSERT ON threads
WHEN NEW.created_at_ms IS NULL
BEGIN
    UPDATE threads
    SET created_at_ms = NEW.created_at * 1000
    WHERE id = NEW.id;
END;
CREATE TRIGGER threads_updated_at_ms_after_insert
AFTER INSERT ON threads
WHEN NEW.updated_at_ms IS NULL
BEGIN
    UPDATE threads
    SET updated_at_ms = NEW.updated_at * 1000
    WHERE id = NEW.id;
END;
CREATE TRIGGER threads_created_at_ms_after_update
AFTER UPDATE OF created_at ON threads
WHEN NEW.created_at != OLD.created_at
 AND NEW.created_at_ms IS OLD.created_at_ms
BEGIN
    UPDATE threads
    SET created_at_ms = NEW.created_at * 1000
    WHERE id = NEW.id;
END;
CREATE TRIGGER threads_updated_at_ms_after_update
AFTER UPDATE OF updated_at ON threads
WHEN NEW.updated_at != OLD.updated_at
 AND NEW.updated_at_ms IS OLD.updated_at_ms
BEGIN
    UPDATE threads
    SET updated_at_ms = NEW.updated_at * 1000
    WHERE id = NEW.id;
END;
CREATE TRIGGER threads_recency_at_after_insert
AFTER INSERT ON threads
WHEN NEW.recency_at_ms = 0
BEGIN
    UPDATE threads
    SET recency_at = NEW.updated_at,
        recency_at_ms = COALESCE(NEW.updated_at_ms, NEW.updated_at * 1000)
    WHERE id = NEW.id;
END;
INSERT INTO _sqlx_migrations (version,description,success,checksum,execution_time) VALUES (1,'fixture',1,X'627EF19164C9BB298A0CD99945981C9B7BDA3D9E6CF12EB35145E3B1D3BF7CF8740F0DBAA0B475185FC2993397078049',0);
INSERT INTO _sqlx_migrations (version,description,success,checksum,execution_time) VALUES (2,'fixture',1,X'521B72CBC04C7D03B1E4AEF8DC0FDEE672F1F7F5881385A55A0E937E4EBE87A3F67BCA4D3F6B59AFBC9A7CA723C82856',0);
INSERT INTO _sqlx_migrations (version,description,success,checksum,execution_time) VALUES (3,'fixture',1,X'E58A2862BDB66D3274E60144A26DC9D68BBEFFF834CD29B82B740F38FCF95862934F412665D985715167839E8F0EB377',0);
INSERT INTO _sqlx_migrations (version,description,success,checksum,execution_time) VALUES (4,'fixture',1,X'8ADC251366E4C7E5EA78B620AC71F4C4BDFB8F048BF9F2FD7204226CFBA54C8E83FC9D83FC1EC334BC683BB7F6D0D8A8',0);
INSERT INTO _sqlx_migrations (version,description,success,checksum,execution_time) VALUES (5,'fixture',1,X'1AC64F85E083E5B49B974BF498FC39C630F0032057FB4BF4CB31708619FAC5A80189F261CF3E38DAFD92DC406E73C220',0);
INSERT INTO _sqlx_migrations (version,description,success,checksum,execution_time) VALUES (6,'fixture',1,X'A203FC4B597E1420BFFDC4E00E214798B21CF7FC921D8BD6F089C75248FB6A4B4942C97A1F8E0271ECA8CF3B3E5E7A80',0);
INSERT INTO _sqlx_migrations (version,description,success,checksum,execution_time) VALUES (7,'fixture',1,X'7E35A464DF6D4C82694DE50865BA3FE9104F9E1385A33BE7D633AB4B8D6CF60B7F369FE083D31251FD77B75FA2D61F82',0);
INSERT INTO _sqlx_migrations (version,description,success,checksum,execution_time) VALUES (8,'fixture',1,X'AA3F287F7A448554E7AF01F259F0871CE90ACE1A7D4B8EBBD74C87AE57C3E21119F7EEC8B9C2E9F4A9E76E63A0F0B60A',0);
INSERT INTO _sqlx_migrations (version,description,success,checksum,execution_time) VALUES (9,'fixture',1,X'8B469360777E6DD6C21D3F0EB93481251846B0A50E0A44EB0DBEE4A0A32B7206768A5D83A5FCEC30C6FD2E43D755FF1B',0);
INSERT INTO _sqlx_migrations (version,description,success,checksum,execution_time) VALUES (10,'fixture',1,X'8ADAF1365F8E5DEEBA68BDEEE9FD83B094A87BDAB364D95AB5C714F7B8BD95DC3B38576871470312154C9D41E8F10F93',0);
INSERT INTO _sqlx_migrations (version,description,success,checksum,execution_time) VALUES (11,'fixture',1,X'31ECECBD07F04452D0DC5127D824ED183056B9900A31AA739387A4AEF232016D975110829814841FB6BF3FD23634B799',0);
INSERT INTO _sqlx_migrations (version,description,success,checksum,execution_time) VALUES (12,'fixture',1,X'0012A213ED25F2CF806C2530C487EBB00B4F102F5960D1A852154A0F77D25C9E9F7DF29550FAEB30EBAFF15A26C7D604',0);
INSERT INTO _sqlx_migrations (version,description,success,checksum,execution_time) VALUES (13,'fixture',1,X'05526A0900A8430523A9A05932EA61302FCE20782B245498565C1B9A2DFD10CF5C49932089B496AE23AF44F6C5F76AF4',0);
INSERT INTO _sqlx_migrations (version,description,success,checksum,execution_time) VALUES (14,'fixture',1,X'4D2FBB2442C5C5C7C47B4254B5B8DC2C52129F65C4A952A79F1EC5C40FB07483326429CE5ACDBD372BC9262352CB6277',0);
INSERT INTO _sqlx_migrations (version,description,success,checksum,execution_time) VALUES (15,'fixture',1,X'0EECE6DB59C948FAA6608526AF440A9F53F5A982D27F3E866CD9F1401C2E59BC61F8381B5A1C9744ACB232F50DB493E5',0);
INSERT INTO _sqlx_migrations (version,description,success,checksum,execution_time) VALUES (16,'fixture',1,X'4768F743E981293735C6E07B0282EC8ACE98AF720059D68555B17979D28C94B0C893A97A950D5E32758BC6D92D8FE6FF',0);
INSERT INTO _sqlx_migrations (version,description,success,checksum,execution_time) VALUES (17,'fixture',1,X'4CBDB2EDFEBF6040858FFC193CFFA36E6B3FBF508F8418AD073081BBFCF59D53D423B6EB4C0DED206AB4D4C1A0EFED94',0);
INSERT INTO _sqlx_migrations (version,description,success,checksum,execution_time) VALUES (18,'fixture',1,X'A4363003BC44F0A4AE1EED53B536B7175F97863EA6881A059DC6642E70E2921576204697CEC2345F560E65FF7FBF4455',0);
INSERT INTO _sqlx_migrations (version,description,success,checksum,execution_time) VALUES (19,'fixture',1,X'3884C02F080F0184E92B620F870DFBB840A8EC5DFCE2FE6455DD8197FCD27D7DD86E63AD6EC7C4091A1161D9ED199F8D',0);
INSERT INTO _sqlx_migrations (version,description,success,checksum,execution_time) VALUES (20,'fixture',1,X'07673F4859F740134569AB9606760D8173ED6DF92DA47C86FBD0CEEB333E18AB7AC91D525AB8C11503C42164FD4167AE',0);
INSERT INTO _sqlx_migrations (version,description,success,checksum,execution_time) VALUES (21,'fixture',1,X'EA1AEBE4F5A1D56C8EFFCC15F705C272275DD8ADFEB01BC97D3F7B283474A3B8C2B0C8C69DE55786E8BDA17CAE6F4DE7',0);
INSERT INTO _sqlx_migrations (version,description,success,checksum,execution_time) VALUES (22,'fixture',1,X'160FE01B757DD06F9573B9030952D021F2B148732BEA5FC5F5AE09E9227F3F83CA676695EDAF8502669FCB546119DC94',0);
INSERT INTO _sqlx_migrations (version,description,success,checksum,execution_time) VALUES (23,'fixture',1,X'E6C748A9A18286E4C773FFE0DAD659F16FB7E5B7B032235815991C405F2D32C068F3EDDE920D0FCF589B687BFFCFEE2E',0);
INSERT INTO _sqlx_migrations (version,description,success,checksum,execution_time) VALUES (24,'fixture',1,X'E92AA526B1F36E26F6221C04A671F07B27DE2E7A5112D93A8C3AF816A87846E7804D5FBAD689E61CF4EC91FD79D3BD8A',0);
INSERT INTO _sqlx_migrations (version,description,success,checksum,execution_time) VALUES (25,'fixture',1,X'D6FB51D79941B93C3278FE2A8A0C6FA882407B7B716E32D72329F0B7B60C181A42F49E56CD552315EFB0402A111EDE12',0);
INSERT INTO _sqlx_migrations (version,description,success,checksum,execution_time) VALUES (26,'fixture',1,X'6C62A325D3B9CA8E424EACB9E3890D8D9DE57C3725E2D1FA30C3743AE779FCA2969387174359DFB26E4920791AE7E831',0);
INSERT INTO _sqlx_migrations (version,description,success,checksum,execution_time) VALUES (27,'fixture',1,X'D84DCA6A039E004C0C7D06C5A16C2CCC363137537F3DD9898F50BB013CE9067140761B87D58CA742D769D35976863FC3',0);
INSERT INTO _sqlx_migrations (version,description,success,checksum,execution_time) VALUES (28,'fixture',1,X'EF44ADAA291E40DFE6B74E3CD259711ADAE13F01C5594B177D08E2D2041A67ED3813FEECF049662AAED0F636BD3F4AC3',0);
INSERT INTO _sqlx_migrations (version,description,success,checksum,execution_time) VALUES (29,'fixture',1,X'E9EC76F97DBF41CE4949DE324A2A26538C2025C0AC4F272B77A852970FB14B7EC970D6978A765F91AE171DCE9C0E4149',0);
INSERT INTO _sqlx_migrations (version,description,success,checksum,execution_time) VALUES (30,'fixture',1,X'80C1CDACD4520B42B18B960164912685591A7EE041645F35609A2EE2792EB474B7B0B758366556982D8CDE2ACB583672',0);
INSERT INTO _sqlx_migrations (version,description,success,checksum,execution_time) VALUES (31,'fixture',1,X'943675A9B3DC92D0B2731AE7D2FE324FF1A40B6366B9D5D8B4CB47CA885C08BEB6EBB1D776A5A47C878B4094DDE70EA0',0);
INSERT INTO _sqlx_migrations (version,description,success,checksum,execution_time) VALUES (32,'fixture',1,X'3C01D615C5E3ABA0FD858B7168E73881598D7D33A0ECC41527BDF6595A199D1AEC2FF9F3B3000A57241C500D81B34259',0);
INSERT INTO _sqlx_migrations (version,description,success,checksum,execution_time) VALUES (33,'fixture',1,X'4904AAE354E3D8CE32AC21D2AE579FD708446AE1DFB2649FC9DD22DC9279B91A2BBB02E6F01B3E0ABD1088177BF2F030',0);
INSERT INTO _sqlx_migrations (version,description,success,checksum,execution_time) VALUES (34,'fixture',1,X'D6FEA739C76EBDEF35A23F06E54EFB5904D7987FB6B663DB1EBC98EB9B192305F454932BFBAA2231AEDCA6209903A5F3',0);
INSERT INTO _sqlx_migrations (version,description,success,checksum,execution_time) VALUES (35,'fixture',1,X'D7B56ACB07C96858BDC7CA4C53DB51EB71C6A19EF2C524FF68C2660A6FE0D23211A6D39CB905F01C42FFB7C8EE913BBC',0);
INSERT INTO _sqlx_migrations (version,description,success,checksum,execution_time) VALUES (36,'fixture',1,X'6381F7BB4C36BE41C6106B8523EA6C68F5A00273A5522155B7B84BAD26D152436F3375DF7097CE3ABF2421AEC32641ED',0);
INSERT INTO _sqlx_migrations (version,description,success,checksum,execution_time) VALUES (37,'fixture',1,X'F6A5AB0DB36BB9E45AB5285B56090FB453DF0A4D4D8D62EACE234F0B557F4203C6C455FC67BD7D6E72623C3979EC9405',0);
INSERT INTO _sqlx_migrations (version,description,success,checksum,execution_time) VALUES (38,'fixture',1,X'E7778522CBE529F5E2BA179B502AEE8E5C21272AD820E672AB0A565F7EDC9BD0F29171CCF9815C0ACC0F89EAE0A2B1FC',0);
INSERT INTO _sqlx_migrations (version,description,success,checksum,execution_time) VALUES (39,'fixture',1,X'C217B3D14C08C23603F485AF11452EE2B68F65FA8DBAF215F33F53B608C092BE8738DE3F63D6A38F120EDEA5AF247C17',0);
INSERT INTO _sqlx_migrations (version,description,success,checksum,execution_time) VALUES (40,'fixture',1,X'A7A99674F90A43184E43D66595C4F1DA50AE8715A5BFCB1579A2B7B10668335D7F7AB6B6F2D7A7A379272773D803A914',0);
INSERT INTO _sqlx_migrations (version,description,success,checksum,execution_time) VALUES (41,'fixture',1,X'0DC734DBE4CBCC5AD5A8BBC2FDC1CF770DDEA3CB53EB36C55A4DA6FA2E8BE4CC8E68672F43AC953E727E415E45C50A78',0);
INSERT INTO _sqlx_migrations (version,description,success,checksum,execution_time) VALUES (42,'fixture',1,X'CFDC4FD47328D1B67C0C7555125DE4FB4ADD5B3B57FD31AC1987E4D8B0C99B1F5418DB9EE7EC2158AED8A2E3DFCFD636',0);
INSERT INTO _sqlx_migrations (version,description,success,checksum,execution_time) VALUES (43,'fixture',1,X'605128E722BD2521C7E979E9961C16706435E442B3E3A8EFA36F6B16C42E3833090906D9A62FDE097A109B78E29DA830',0);
INSERT INTO _sqlx_migrations (version,description,success,checksum,execution_time) VALUES (44,'fixture',1,X'5D29223BD1CAFE456A4AF992A545E8EC420B71331EB12A7427E26512B8A44117D9445B83562F095B3A5A0F11C4F091D2',0);
INSERT INTO _sqlx_migrations (version,description,success,checksum,execution_time) VALUES (45,'fixture',1,X'A7FADC8CAEA8B6ABEB108F588A91B8E5D1C9E2645CE990F2251B9F0234E6E53D78FC854F1C88C7217CC143016539D691',0);
INSERT INTO _sqlx_migrations (version,description,success,checksum,execution_time) VALUES (46,'fixture',1,X'63ADDF6115C3FB1A22A886108CE6EBFF5CD8408F219606DC2F8396836418E56D5BE2A6DE7B0DF877119A28096EE67D22',0);
INSERT INTO _sqlx_migrations (version,description,success,checksum,execution_time) VALUES (47,'fixture',1,X'1AE117E4AB40813DE2B6CFED521585A5396A8DCB7277923D539ED111F5E76424787131EF1DE353BE5DD78E8228F204CC',0);
INSERT INTO _sqlx_migrations (version,description,success,checksum,execution_time) VALUES (48,'fixture',1,X'9D298333F7523010502044685009FFE1ED18C3FED7F01FB200D62252F90AB0D897CCF05E478F90150B941EA6C0BD459C',0);
INSERT INTO _sqlx_migrations (version,description,success,checksum,execution_time) VALUES (49,'fixture',1,X'FAF45C392BB8572062BBD52F9702966CF62E3D195A1633F54CFE1B7DCB5865A3F951DC75C975179DC9A0EE639F7426A7',0);
INSERT INTO _sqlx_migrations (version,description,success,checksum,execution_time) VALUES (50,'fixture',1,X'D2802E96F5FC1900FC6D3D595F040EBCA8D25310AE9D1499A12B91F1635617ADF5D2B4A93D0807203A22F4A6D4EDB77E',0);
INSERT INTO _sqlx_migrations (version,description,success,checksum,execution_time) VALUES (51,'fixture',1,X'23360A03A7FC307C3FD5BB8B432B66034DD8F8695CDBA698B45278C20DD712C1AF476B884E192237D80BAA08A5F29505',0);
INSERT INTO _sqlx_migrations (version,description,success,checksum,execution_time) VALUES (52,'fixture',1,X'071E96313D402E4C3D156F620F3F62B4A468DA00CE30A47574D2594623E5E954F3EC2F1E54F043A8E4B602643E868B7D',0);
INSERT INTO _sqlx_migrations (version,description,success,checksum,execution_time) VALUES (53,'fixture',1,X'E86EF7CCBCC891B1AF27F6AEDB26BFE36D79C9D405E48F302EB053CB57FF9B24DBEB0479B48B18E2076EFB6BFC4A9287',0);
INSERT INTO _sqlx_migrations (version,description,success,checksum,execution_time) VALUES (54,'fixture',1,X'E62A9977D99C7EABF36B67B183D86443D062B0AA8D018C42D1299821DE4BF59182E16494AB874FD2D4081EF510E759F1',0);
INSERT INTO _sqlx_migrations (version,description,success,checksum,execution_time) VALUES (55,'fixture',1,X'6DAADC5527B3F57FA360C5D93199282BA54A42B7598558A9765BD6DCF11F555150FE678ED8163ABB2E1861CB51D196C3',0);
INSERT INTO _sqlx_migrations (version,description,success,checksum,execution_time) VALUES (56,'fixture',1,X'5DE44FAC5505249BE66FCD640E9AC3D36550854C0DB1272EB52CBB6C3D18B207DB4CB782686D81089E77EBB57F6819B1',0);
INSERT INTO _sqlx_migrations (version,description,success,checksum,execution_time) VALUES (57,'fixture',1,X'729562C57BFA8B43D5AE3476C99CEF6E81A54709A74283057CE8D2D6F55CF8EAE2594FDB7CFF4238EBE1E481E7C049E6',0);
INSERT INTO _sqlx_migrations (version,description,success,checksum,execution_time) VALUES (58,'fixture',1,X'68467AF3CE1FF09777C3F7167D522E11D88586FBB80A1588C631CF643A7D4985B221A6C8E8623997B37D44605B7E1091',0);
INSERT INTO _sqlx_migrations (version,description,success,checksum,execution_time) VALUES (59,'fixture',1,X'4297DFFB4FB308F0C665E4D126B7D2A96DB7BE48EB2E13C7E1245A5D95C4DF4E66D64E79AD00FEC26B0910436703090C',0);
INSERT INTO _sqlx_migrations (version,description,success,checksum,execution_time) VALUES (60,'fixture',1,X'D7F0CF0A69FA71999AFFCD48CC74B2D0A2637B8BBDA73BD5819547CCDB15543A75D239311FA07FCF699BE9BCBC1874A8',0);
INSERT INTO _sqlx_migrations (version,description,success,checksum,execution_time) VALUES (61,'fixture',1,X'4A8337048BB958A21FD5272C1BD670605C84D4063534270D3E41CDC5C5A2E865F0FE6AE3C336DED873877EE2EA10F2E0',0);
