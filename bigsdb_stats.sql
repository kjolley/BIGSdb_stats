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

CREATE TABLE isolates_date_entered (
	datestamp date NOT NULL,
	dbase_config text NOT NULL,
	count int NOT NULL,
	PRIMARY KEY (datestamp,dbase_config),
	CONSTRAINT ide_dbase_config FOREIGN KEY (dbase_config) REFERENCES resources
	ON DELETE CASCADE
	ON UPDATE CASCADE
);

CREATE TABLE isolates_last_modified (
	datestamp date NOT NULL,
	dbase_config text NOT NULL,
	count int NOT NULL,
	PRIMARY KEY (datestamp,dbase_config),
	CONSTRAINT ilm_dbase_config FOREIGN KEY (dbase_config) REFERENCES resources
	ON DELETE CASCADE
	ON UPDATE CASCADE
);


CREATE TABLE genomes_date_entered (
	datestamp date NOT NULL,
	dbase_config text NOT NULL,
	count int NOT NULL,
	PRIMARY KEY (datestamp,dbase_config),
	CONSTRAINT gde_dbase_config FOREIGN KEY (dbase_config) REFERENCES resources
	ON DELETE CASCADE
	ON UPDATE CASCADE
);

CREATE TABLE genomes_last_modified (
	datestamp date NOT NULL,
	dbase_config text NOT NULL,
	count int NOT NULL,
	PRIMARY KEY (datestamp,dbase_config),
	CONSTRAINT glm_dbase_config FOREIGN KEY (dbase_config) REFERENCES resources
	ON DELETE CASCADE
	ON UPDATE CASCADE
);

CREATE TABLE sequences_date_entered (
	datestamp date NOT NULL,
	dbase_config text NOT NULL,
	count int NOT NULL,
	PRIMARY KEY (datestamp,dbase_config),
	CONSTRAINT sde_dbase_config FOREIGN KEY (dbase_config) REFERENCES resources
	ON DELETE CASCADE
	ON UPDATE CASCADE
);

CREATE TABLE sequences_last_modified (
	datestamp date NOT NULL,
	dbase_config text NOT NULL,
	count int NOT NULL,
	PRIMARY KEY (datestamp,dbase_config),
	CONSTRAINT slm_dbase_config FOREIGN KEY (dbase_config) REFERENCES resources
	ON DELETE CASCADE
	ON UPDATE CASCADE
);

CREATE TABLE profiles_date_entered (
	datestamp date NOT NULL,
	dbase_config text NOT NULL,
	scheme text NOT NULL,
	scheme_id int NOT NULL,
	count int NOT NULL,
	PRIMARY KEY (datestamp,dbase_config,scheme),
	CONSTRAINT pde_dbase_config FOREIGN KEY (dbase_config) REFERENCES resources
	ON DELETE CASCADE
	ON UPDATE CASCADE
);

CREATE TABLE profiles_last_modified (
	datestamp date NOT NULL,
	dbase_config text NOT NULL,
	scheme text NOT NULL,
	scheme_id int NOT NULL,
	count int NOT NULL,
	PRIMARY KEY (datestamp,dbase_config,scheme),
	CONSTRAINT plm_dbase_config FOREIGN KEY (dbase_config) REFERENCES resources
	ON DELETE CASCADE
	ON UPDATE CASCADE
);

CREATE TABLE countries (
	dbase_config text NOT NULL,
	country text NOT NULL,
	count int NOT NULL,
	genomes int NOT NULL,
	PRIMARY KEY (dbase_config,country),
	CONSTRAINT c_dbase_config FOREIGN KEY (dbase_config) REFERENCES resources
	ON DELETE CASCADE
	ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON resources,sets,set_resources,isolates_date_entered,
isolates_last_modified,genomes_date_entered,genomes_last_modified,sequences_date_entered,
sequences_last_modified,profiles_date_entered,profiles_last_modified,countries TO apache;
