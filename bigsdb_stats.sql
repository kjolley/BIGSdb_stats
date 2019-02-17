CREATE TABLE resources (
	dbase_config text NOT NULL,
	description text NOT NULL,
	PRIMARY KEY (dbase_config)
);

CREATE TABLE sets (
	name text NOT NULL,
	isolates int NOT NULL DEFAULT 0,
	genomes int NOT NULL DEFAULT 0,
	sequences int NOT NULL DEFAULT 0,
	PRIMARY KEY (name)
);

CREATE TABLE set_resources (
	set_name text NOT NULL,
	dbase_config text NOT NULL,
	PRIMARY KEY (set_name,dbase_config),
	CONSTRAINT sr_set_name FOREIGN KEY (set_name) REFERENCES sets
	ON DELETE CASCADE
	ON UPDATE CASCADE,
	CONSTRAINT sr_dbase_config FOREIGN KEY (dbase_config) REFERENCES resources
	ON DELETE CASCADE
	ON UPDATE CASCADE
);

CREATE TABLE isolates (
	datestamp date NOT NULL,
	dbase_config text NOT NULL,
	count int NOT NULL,
	PRIMARY KEY (datestamp,dbase_config),
	CONSTRAINT i_dbase_config FOREIGN KEY (dbase_config) REFERENCES resources
	ON DELETE CASCADE
	ON UPDATE CASCADE
);

CREATE TABLE genomes (
	datestamp date NOT NULL,
	dbase_config text NOT NULL,
	count int NOT NULL,
	PRIMARY KEY (datestamp,dbase_config),
	CONSTRAINT g_dbase_config FOREIGN KEY (dbase_config) REFERENCES resources
	ON DELETE CASCADE
	ON UPDATE CASCADE
);

CREATE TABLE sequences (
	datestamp date NOT NULL,
	dbase_config text NOT NULL,
	count int NOT NULL,
	PRIMARY KEY (datestamp,dbase_config),
	CONSTRAINT s_dbase_config FOREIGN KEY (dbase_config) REFERENCES resources
	ON DELETE CASCADE
	ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON resources,sets,set_resources,isolates,genomes,sequences TO apache;
