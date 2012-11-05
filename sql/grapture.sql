--
-- PostgreSQL database dump
--

-- Dumped from database version 9.1.6
-- Dumped by pg_dump version 9.1.6
-- Started on 2012-11-06 06:13:36 EST

SET statement_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SET check_function_bodies = false;
SET client_min_messages = warning;

--
-- TOC entry 1963 (class 1262 OID 25641)
-- Name: grapture; Type: DATABASE; Schema: -; Owner: grapture
--

CREATE DATABASE grapture WITH TEMPLATE = template0 ENCODING = 'UTF8' LC_COLLATE = 'en_AU.UTF-8' LC_CTYPE = 'en_AU.UTF-8';


ALTER DATABASE grapture OWNER TO grapture;

\connect grapture

SET statement_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SET check_function_bodies = false;
SET client_min_messages = warning;

--
-- TOC entry 169 (class 3079 OID 11681)
-- Name: plpgsql; Type: EXTENSION; Schema: -; Owner: 
--

CREATE EXTENSION IF NOT EXISTS plpgsql WITH SCHEMA pg_catalog;


--
-- TOC entry 1966 (class 0 OID 0)
-- Dependencies: 169
-- Name: EXTENSION plpgsql; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION plpgsql IS 'PL/pgSQL procedural language';


SET search_path = public, pg_catalog;

--
-- TOC entry 181 (class 1255 OID 25642)
-- Dependencies: 6 524
-- Name: add_alarmdef(character varying, character varying, character varying, integer, character varying, character varying, character varying, integer, integer, boolean); Type: FUNCTION; Schema: public; Owner: grapture
--

CREATE FUNCTION add_alarmdef(target character varying, device character varying, metric character varying, valspan integer, threshtype character varying, comparisontype character varying, trapdest character varying, warn integer, crit integer, disabled boolean) RETURNS integer
    LANGUAGE plpgsql
    AS $_$

    DECLARE
        
    BEGIN
        -- Any errors or inconsistancies raise exceptions so that in
        -- code we just have to look for a true execute() statement
        -- without having to actually fetch the result (0, null etc are
        -- valid returns).

        --
        -- START adding data
        --
        EXECUTE 'INSERT INTO alarmdefs ( target, device, metric, valspan, threshtype, comparisontype, trapdest, warn, crit, disabled )
          VALUES ( $1, $2, $3, $4, $5, $6, $7 )'
          USING target, device, metric, valspan, threshtype, comparisontype, trapdest, warn, crit, disabled;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'Failed to create trapdest';
        END IF;

        RETURN 1;
    END;
$_$;


ALTER FUNCTION public.add_alarmdef(target character varying, device character varying, metric character varying, valspan integer, threshtype character varying, comparisontype character varying, trapdest character varying, warn integer, crit integer, disabled boolean) OWNER TO grapture;

--
-- TOC entry 182 (class 1255 OID 25643)
-- Dependencies: 524 6
-- Name: add_group(character varying, character varying); Type: FUNCTION; Schema: public; Owner: grapture
--

CREATE FUNCTION add_group(new_group character varying, new_memberof character varying) RETURNS integer
    LANGUAGE plpgsql
    AS $$

DECLARE
    existing_group groupings%ROWTYPE;
    existing_parent groupings%ROWTYPE;

BEGIN
    -- Check that the new group does not already exist.
    SELECT * INTO existing_group FROM groupings WHERE groupname = new_group;

    IF NOT FOUND THEN

        -- Check the parent group exists unless its null.
        SELECT * INTO existing_parent FROM groupings WHERE groupname = new_memberof;
        IF FOUND OR new_memberof IS NULL THEN

            -- Do an INSERT
            INSERT INTO groupings (groupname, memberof)
              VALUES (new_group, new_memberof);
            
            IF NOT FOUND THEN
                RAISE EXCEPTION 'FAILED TO INSERT GROUP';
            END IF;

        END IF;
    
    END IF;
    
    RETURN 1;
    
END;
$$;


ALTER FUNCTION public.add_group(new_group character varying, new_memberof character varying) OWNER TO grapture;

--
-- TOC entry 184 (class 1255 OID 25644)
-- Dependencies: 524 6
-- Name: add_or_update_target(character varying, integer, character varying, character varying, integer); Type: FUNCTION; Schema: public; Owner: grapture
--

CREATE FUNCTION add_or_update_target(new_target character varying, new_snmpversion integer, new_snmpcommunity character varying, new_groupname character varying, rediscover integer) RETURNS integer
    LANGUAGE plpgsql
    AS $$

DECLARE
    existing_target targets%ROWTYPE;

BEGIN
    IF new_groupname IS NULL OR new_groupname = '' THEN
        new_groupname := 'Unknown';
    END IF;
    
    SELECT * INTO existing_target FROM targets WHERE target = new_target;
    IF NOT FOUND THEN
        -- Do an INSERT
        INSERT INTO targets (target, snmpversion, snmpcommunity, groupname)
          VALUES (new_target, new_snmpversion, new_snmpcommunity, new_groupname);
        
        IF NOT FOUND THEN
            RAISE EXCEPTION 'FAILED TO INSERT TARGET';
        END IF;        
    ELSE
        -- Do an UPDATE where target = target
        -- DO NOT UPDATE the target name.
        IF rediscover > 0 or rediscover IS NOT NULL THEN
            -- NULL the lastdicovered to trigger rediscover
            UPDATE targets SET 
              snmpversion    = new_snmpversion,
              snmpcommunity  = new_snmpcommunity,
              groupname      = new_groupname,
              lastdiscovered = NULL
              
              WHERE target = new_target;
            
            IF NOT FOUND THEN
                RAISE EXCEPTION 'FAILED TO UPDATE TARGET';
            END IF;        

        ELSE
            -- Leave the lastdiscovered alone
            UPDATE targets SET 
              snmpversion    = new_snmpversion,
              snmpcommunity  = new_snmpcommunity,
              groupname      = new_groupname
              
              WHERE target = new_target;
            
            IF NOT FOUND THEN
                RAISE EXCEPTION 'FAILED TO UPDATE TARGET';
            END IF;        
            
        END IF;
        
    END IF;
    
    RETURN 1;

END;
$$;


ALTER FUNCTION public.add_or_update_target(new_target character varying, new_snmpversion integer, new_snmpcommunity character varying, new_groupname character varying, rediscover integer) OWNER TO grapture;

--
-- TOC entry 185 (class 1255 OID 25645)
-- Dependencies: 524 6
-- Name: add_or_update_target_metric(character varying, character varying, character varying, character varying, integer, character varying, character varying, character varying, character varying, character varying, character varying, boolean, integer, boolean, character varying); Type: FUNCTION; Schema: public; Owner: grapture
--

CREATE FUNCTION add_or_update_target_metric(new_target character varying, new_device character varying, new_metric character varying, new_mapbase character varying, new_counterbits integer, new_modules character varying, new_valbase character varying, new_max character varying, new_category character varying, new_valtype character varying, new_graphgroup character varying, new_enabled boolean, new_graphorder integer, new_aggregate boolean, new_conversion character varying) RETURNS integer
    LANGUAGE plpgsql
    AS $$

DECLARE
    existing_metric targetmetrics%ROWTYPE;

BEGIN
    
    SELECT * INTO existing_metric FROM targetmetrics 
      WHERE target = new_target 
      and device = new_device 
      and metric = new_metric;

    IF NOT FOUND THEN
        -- Do an INSERT
        INSERT INTO targetmetrics 
          (
              target,  device,     metric,  mapbase,    counterbits,
              modules, valbase,    max,     category,   valtype,
              graphgroup, enabled, graphorder, aggregate, conversion
          )
        VALUES 
          (
              new_target,  new_device,     new_metric,  new_mapbase,      new_counterbits,
              new_modules, new_valbase,    new_max,     new_category,     new_valtype,
              new_graphgroup, new_enabled, new_graphorder, new_aggregate, new_conversion
          );
        
        IF NOT FOUND THEN
            RAISE EXCEPTION 'FAILED TO INSERT TARGET METRIC';
        END IF;        
        
    ELSE
        -- Do an UPDATE 
        -- DO NOT UPDATE the target device or metric.
        UPDATE targetmetrics SET 
          target      = new_target,      device     = new_device,
          metric      = new_metric,      mapbase    = new_mapbase,
          counterbits = new_counterbits, modules    = new_modules,
          valbase     = new_valbase,     max        = new_max,
          category    = new_category,    valtype    = new_valtype,
          graphgroup  = new_graphgroup,  enabled    = new_enabled,
          graphorder  = new_graphorder,  aggregate  = new_aggregate,
          conversion  = new_conversion

          WHERE target = new_target 
          and device   = new_device 
          and metric   = new_metric;
        
        IF NOT FOUND THEN
            RAISE EXCEPTION 'FAILED TO UPDATE TARGET METRIC';
        END IF;        
        
    END IF;
    
    RETURN 1;

END;
$$;


ALTER FUNCTION public.add_or_update_target_metric(new_target character varying, new_device character varying, new_metric character varying, new_mapbase character varying, new_counterbits integer, new_modules character varying, new_valbase character varying, new_max character varying, new_category character varying, new_valtype character varying, new_graphgroup character varying, new_enabled boolean, new_graphorder integer, new_aggregate boolean, new_conversion character varying) OWNER TO grapture;

--
-- TOC entry 186 (class 1255 OID 25646)
-- Dependencies: 6 524
-- Name: add_trapdest(character varying, integer, character varying); Type: FUNCTION; Schema: public; Owner: grapture
--

CREATE FUNCTION add_trapdest(hostname character varying, snmpversion integer, snmpcommunity character varying) RETURNS integer
    LANGUAGE plpgsql
    AS $_$

    DECLARE
        
    BEGIN
        -- Any errors or inconsistancies raise exceptions so that in
        -- code we just have to look for a true execute() statement
        -- without having to actually fetch the result (0, null etc are
        -- valid returns).

        --
        -- START adding data
        --
        EXECUTE 'INSERT INTO trapdests ( hostname, snmpversion, snmpcommunity )
          VALUES ( $1, $2, $3 )'
          USING hostname, snmpversion, snmpcommunity;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'Failed to create trapdest';
        END IF;

        RETURN 1;
    END;
$_$;


ALTER FUNCTION public.add_trapdest(hostname character varying, snmpversion integer, snmpcommunity character varying) OWNER TO grapture;

--
-- TOC entry 183 (class 1255 OID 25647)
-- Dependencies: 6 524
-- Name: target_discovered(character varying); Type: FUNCTION; Schema: public; Owner: grapture
--

CREATE FUNCTION target_discovered(disc_target character varying) RETURNS integer
    LANGUAGE plpgsql
    AS $$

DECLARE

BEGIN
    -- Do an UPDATE where target = target
    UPDATE targets SET 
      lastdiscovered = LOCALTIMESTAMP
      WHERE target = disc_target;
    
    IF NOT FOUND THEN
        RAISE EXCEPTION 'FAILED TO UPDATE TARGET';
    END IF;        

    RETURN 1;

END;
$$;


ALTER FUNCTION public.target_discovered(disc_target character varying) OWNER TO grapture;

--
-- TOC entry 187 (class 1255 OID 25839)
-- Dependencies: 524 6
-- Name: update_alarm(character varying, character varying, character varying, integer, real); Type: FUNCTION; Schema: public; Owner: grapture
--

CREATE FUNCTION update_alarm(new_target character varying, new_device character varying, new_metric character varying, new_severity integer, new_value real) RETURNS integer
    LANGUAGE plpgsql
    AS $_$

    DECLARE
        existing_alarm RECORD;
        
    BEGIN
        -- Any errors or inconsistancies raise exceptions so that in
        -- code we just have to look for a true execute() statement
        -- without having to actually fetch the result (0, null etc are
        -- valid returns).

        IF new_severity = 1 THEN
            -- The state is ok, close any alarms
            EXECUTE 'UPDATE alarms SET active = false
              WHERE target = $1 and device = $2 and metric = $3'
              USING new_target, new_device, new_metric;
            
            IF NOT FOUND THEN
                RAISE EXCEPTION 'Failed to register alarm';
            END IF;

        ELSIF new_severity > 1 THEN
            -- get any exisiting alarm, if the state is the same but the
            -- new val is bigger, just update the value.  If the state 
            -- is different, close the old alarm and log a new one.
            SELECT severity, value INTO existing_alarm FROM alarms
              WHERE target = new_target and device = new_device and metric = new_metric and active = true;
               
              --USING new_target, new_device, new_metric;
            
            IF NOT FOUND THEN
                -- Add a new alarm
                RAISE LOG 'No exising alarm found. Creating new one.';
                EXECUTE 'INSERT INTO alarms (target, device, metric, severity, value, active)
                  VALUES ( $1, $2, $3, $4, $5, true)'
                  USING new_target, new_device, new_metric, new_severity, new_value;
                  
            ELSIF new_severity <> existing_alarm.severity THEN
                -- Severity has changed, close off the old alarm
                RAISE LOG 'Severity has changed, close old alarm and raise a new one';
                EXECUTE 'UPDATE alarms SET active = false
                  WHERE target = $1 and device = $2 and metric = $3'
                  USING new_target, new_device, new_metric;
                
                IF NOT FOUND THEN
                    RAISE EXCEPTION 'Failed to register alarm';
                END IF;

                -- Add a new alarm
                EXECUTE 'INSERT INTO alarms (target, device, metric, severity, value, active)
                  VALUES ( $1, $2, $3, $4, $5, true)'
                  USING new_target, new_device, new_metric, new_severity, new_value;
                
                IF NOT FOUND THEN
                    RAISE EXCEPTION 'Failed to register alarm';
                END IF;
    
            ELSIF new_severity = existing_alarm.severity and new_value > existing_alarm.value THEN
                -- Severity is the same but the new value is bigger, update the value of the current alarm
                RAISE LOG 'Severity is the same but the value has gotten worse, update the existing alarm';
                EXECUTE 'UPDATE alarms SET value = $1
                  WHERE target = $2 and device = $3 and metric = $4 and active = true'
                  USING new_value, new_target, new_device, new_metric;       
            
            END IF;
        END IF;
            
        RETURN 1;
    END;
$_$;


ALTER FUNCTION public.update_alarm(new_target character varying, new_device character varying, new_metric character varying, new_severity integer, new_value real) OWNER TO grapture;

SET default_tablespace = '';

SET default_with_oids = false;

--
-- TOC entry 161 (class 1259 OID 25649)
-- Dependencies: 1924 6
-- Name: alarmdefs; Type: TABLE; Schema: public; Owner: grapture; Tablespace: 
--

CREATE TABLE alarmdefs (
    target character varying(255) NOT NULL,
    metric character varying(255) NOT NULL,
    device character varying(255) NOT NULL,
    valspan integer NOT NULL,
    threshtype character varying(255) NOT NULL,
    comparisontype character varying(255) NOT NULL,
    trapdest character varying(255),
    warn integer NOT NULL,
    crit integer NOT NULL,
    disabled boolean DEFAULT false NOT NULL
);


ALTER TABLE public.alarmdefs OWNER TO grapture;

--
-- TOC entry 1967 (class 0 OID 0)
-- Dependencies: 161
-- Name: COLUMN alarmdefs.threshtype; Type: COMMENT; Schema: public; Owner: grapture
--

COMMENT ON COLUMN alarmdefs.threshtype IS 'Type of threshold value (percentage)';


--
-- TOC entry 1968 (class 0 OID 0)
-- Dependencies: 161
-- Name: COLUMN alarmdefs.comparisontype; Type: COMMENT; Schema: public; Owner: grapture
--

COMMENT ON COLUMN alarmdefs.comparisontype IS 'Type of comparison (average, all_over, majority_over)';


--
-- TOC entry 162 (class 1259 OID 25656)
-- Dependencies: 1925 1926 6
-- Name: alarms; Type: TABLE; Schema: public; Owner: grapture; Tablespace: 
--

CREATE TABLE alarms (
    target character varying(50) NOT NULL,
    device character varying(50) NOT NULL,
    metric character varying(50) NOT NULL,
    value real NOT NULL,
    "timestamp" timestamp without time zone DEFAULT now() NOT NULL,
    active boolean DEFAULT false NOT NULL,
    severity integer NOT NULL
);


ALTER TABLE public.alarms OWNER TO grapture;

--
-- TOC entry 163 (class 1259 OID 25660)
-- Dependencies: 6
-- Name: graphgroupsettings; Type: TABLE; Schema: public; Owner: grapture; Tablespace: 
--

CREATE TABLE graphgroupsettings (
    graphgroup character varying(50),
    fill boolean,
    stack boolean,
    mirror boolean,
    percent boolean
);


ALTER TABLE public.graphgroupsettings OWNER TO grapture;

--
-- TOC entry 164 (class 1259 OID 25663)
-- Dependencies: 6
-- Name: groupings; Type: TABLE; Schema: public; Owner: grapture; Tablespace: 
--

CREATE TABLE groupings (
    groupname character varying(30) NOT NULL,
    memberof character varying(50)
);


ALTER TABLE public.groupings OWNER TO grapture;

--
-- TOC entry 165 (class 1259 OID 25666)
-- Dependencies: 6
-- Name: targetmetrics; Type: TABLE; Schema: public; Owner: grapture; Tablespace: 
--

CREATE TABLE targetmetrics (
    target character varying(50) NOT NULL,
    device character varying(50) NOT NULL,
    metric character varying(50) NOT NULL,
    mapbase character varying(500),
    counterbits integer,
    modules character varying(50) NOT NULL,
    valbase character varying(500) NOT NULL,
    max character varying(50),
    category character varying(50),
    valtype character varying(50),
    graphgroup character varying(50),
    enabled boolean,
    graphorder integer,
    aggregate boolean,
    conversion character varying(255)
);


ALTER TABLE public.targetmetrics OWNER TO grapture;

--
-- TOC entry 166 (class 1259 OID 25672)
-- Dependencies: 6
-- Name: targets; Type: TABLE; Schema: public; Owner: grapture; Tablespace: 
--

CREATE TABLE targets (
    target character varying(50) NOT NULL,
    snmpversion integer NOT NULL,
    snmpcommunity character varying(50) NOT NULL,
    lastdiscovered timestamp without time zone,
    groupname character varying(50)
);


ALTER TABLE public.targets OWNER TO grapture;

--
-- TOC entry 167 (class 1259 OID 25675)
-- Dependencies: 6
-- Name: trapdests; Type: TABLE; Schema: public; Owner: grapture; Tablespace: 
--

CREATE TABLE trapdests (
    hostname character varying(255) NOT NULL,
    snmpversion integer[] NOT NULL,
    snmpcommunity character varying(255) NOT NULL
);


ALTER TABLE public.trapdests OWNER TO grapture;

--
-- TOC entry 168 (class 1259 OID 25681)
-- Dependencies: 6
-- Name: users; Type: TABLE; Schema: public; Owner: grapture; Tablespace: 
--

CREATE TABLE users (
    username character varying(50) NOT NULL,
    password character varying(200) NOT NULL
);


ALTER TABLE public.users OWNER TO grapture;

--
-- TOC entry 1951 (class 0 OID 25649)
-- Dependencies: 161 1959
-- Data for Name: alarmdefs; Type: TABLE DATA; Schema: public; Owner: grapture
--

COPY alarmdefs (target, metric, device, valspan, threshtype, comparisontype, trapdest, warn, crit, disabled) FROM stdin;
bishop.portman.int	SpaceUsed	/srv/storage01	5	percent	average	\N	50	55	f
\.


--
-- TOC entry 1952 (class 0 OID 25656)
-- Dependencies: 162 1959
-- Data for Name: alarms; Type: TABLE DATA; Schema: public; Owner: grapture
--

COPY alarms (target, device, metric, value, "timestamp", active, severity) FROM stdin;
bishop.portman.int	/srv/storage01	SpaceUsed	55.787632	2012-11-06 05:35:14.682872	t	3
\.


--
-- TOC entry 1953 (class 0 OID 25660)
-- Dependencies: 163 1959
-- Data for Name: graphgroupsettings; Type: TABLE DATA; Schema: public; Owner: grapture
--

COPY graphgroupsettings (graphgroup, fill, stack, mirror, percent) FROM stdin;
InterfaceTraffic	t	f	t	\N
InterfaceErrors	t	f	t	\N
MemoryUsage	t	t	f	\N
StorageIOBytes	t	f	t	\N
StorageIOCount	t	f	t	\N
CPUUsage	t	t	f	\N
SpaceUsed	t	f	f	t
SpaceUsedPercent	t	f	f	t
\.


--
-- TOC entry 1954 (class 0 OID 25663)
-- Dependencies: 164 1959
-- Data for Name: groupings; Type: TABLE DATA; Schema: public; Owner: grapture
--

COPY groupings (groupname, memberof) FROM stdin;
Unknown	\N
\.

--
-- TOC entry 1957 (class 0 OID 25675)
-- Dependencies: 167 1959
-- Data for Name: trapdests; Type: TABLE DATA; Schema: public; Owner: grapture
--

COPY trapdests (hostname, snmpversion, snmpcommunity) FROM stdin;
\.


--
-- TOC entry 1958 (class 0 OID 25681)
-- Dependencies: 168 1959
-- Data for Name: users; Type: TABLE DATA; Schema: public; Owner: grapture
--

COPY users (username, password) FROM stdin;
admin	5f4dcc3b5aa765d61d8327deb882cf99
\.


--
-- TOC entry 1928 (class 2606 OID 25685)
-- Dependencies: 161 161 161 1960
-- Name: alarmdefs_pkey; Type: CONSTRAINT; Schema: public; Owner: grapture; Tablespace: 
--

ALTER TABLE ONLY alarmdefs
    ADD CONSTRAINT alarmdefs_pkey PRIMARY KEY (target, metric);


--
-- TOC entry 1931 (class 2606 OID 25687)
-- Dependencies: 162 162 162 162 162 1960
-- Name: alarms_pkey; Type: CONSTRAINT; Schema: public; Owner: grapture; Tablespace: 
--

ALTER TABLE ONLY alarms
    ADD CONSTRAINT alarms_pkey PRIMARY KEY (target, device, metric, "timestamp");


--
-- TOC entry 1935 (class 2606 OID 25689)
-- Dependencies: 164 164 1960
-- Name: groupings_pkey; Type: CONSTRAINT; Schema: public; Owner: grapture; Tablespace: 
--

ALTER TABLE ONLY groupings
    ADD CONSTRAINT groupings_pkey PRIMARY KEY (groupname);


--
-- TOC entry 1942 (class 2606 OID 25691)
-- Dependencies: 166 166 1960
-- Name: target; Type: CONSTRAINT; Schema: public; Owner: grapture; Tablespace: 
--

ALTER TABLE ONLY targets
    ADD CONSTRAINT target PRIMARY KEY (target);


--
-- TOC entry 1938 (class 2606 OID 25693)
-- Dependencies: 165 165 165 165 1960
-- Name: target_device_metric; Type: CONSTRAINT; Schema: public; Owner: grapture; Tablespace: 
--

ALTER TABLE ONLY targetmetrics
    ADD CONSTRAINT target_device_metric PRIMARY KEY (target, device, metric);


--
-- TOC entry 1944 (class 2606 OID 25695)
-- Dependencies: 167 167 1960
-- Name: trapdests_pkey; Type: CONSTRAINT; Schema: public; Owner: grapture; Tablespace: 
--

ALTER TABLE ONLY trapdests
    ADD CONSTRAINT trapdests_pkey PRIMARY KEY (hostname);


--
-- TOC entry 1946 (class 2606 OID 25697)
-- Dependencies: 168 168 1960
-- Name: username; Type: CONSTRAINT; Schema: public; Owner: grapture; Tablespace: 
--

ALTER TABLE ONLY users
    ADD CONSTRAINT username PRIMARY KEY (username);


--
-- TOC entry 1929 (class 1259 OID 25698)
-- Dependencies: 161 1960
-- Name: fki_alarmdefs_trapdests_fkey; Type: INDEX; Schema: public; Owner: grapture; Tablespace: 
--

CREATE INDEX fki_alarmdefs_trapdests_fkey ON alarmdefs USING btree (trapdest);


--
-- TOC entry 1932 (class 1259 OID 25699)
-- Dependencies: 162 1960
-- Name: fki_alarms_target_fkey; Type: INDEX; Schema: public; Owner: grapture; Tablespace: 
--

CREATE INDEX fki_alarms_target_fkey ON alarms USING btree (target);


--
-- TOC entry 1936 (class 1259 OID 25700)
-- Dependencies: 165 1960
-- Name: fki_target; Type: INDEX; Schema: public; Owner: grapture; Tablespace: 
--

CREATE INDEX fki_target ON targetmetrics USING btree (target);


--
-- TOC entry 1940 (class 1259 OID 25701)
-- Dependencies: 166 1960
-- Name: fki_valid_group; Type: INDEX; Schema: public; Owner: grapture; Tablespace: 
--

CREATE INDEX fki_valid_group ON targets USING btree (groupname);


--
-- TOC entry 1933 (class 1259 OID 25702)
-- Dependencies: 162 162 162 1960
-- Name: target_device_metric_idx; Type: INDEX; Schema: public; Owner: grapture; Tablespace: 
--

CREATE INDEX target_device_metric_idx ON alarms USING btree (target, device, metric);


--
-- TOC entry 1939 (class 1259 OID 25703)
-- Dependencies: 165 165 1960
-- Name: target_devices; Type: INDEX; Schema: public; Owner: grapture; Tablespace: 
--

CREATE INDEX target_devices ON targetmetrics USING btree (target, device);


--
-- TOC entry 1947 (class 2606 OID 25704)
-- Dependencies: 167 161 1943 1960
-- Name: alarmdefs_trapdests_fkey; Type: FK CONSTRAINT; Schema: public; Owner: grapture
--

ALTER TABLE ONLY alarmdefs
    ADD CONSTRAINT alarmdefs_trapdests_fkey FOREIGN KEY (trapdest) REFERENCES trapdests(hostname) ON UPDATE CASCADE ON DELETE SET NULL;


--
-- TOC entry 1948 (class 2606 OID 25709)
-- Dependencies: 166 162 1941 1960
-- Name: alarms_target_fkey; Type: FK CONSTRAINT; Schema: public; Owner: grapture
--

ALTER TABLE ONLY alarms
    ADD CONSTRAINT alarms_target_fkey FOREIGN KEY (target) REFERENCES targets(target) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 1949 (class 2606 OID 25714)
-- Dependencies: 165 1941 166 1960
-- Name: target; Type: FK CONSTRAINT; Schema: public; Owner: grapture
--

ALTER TABLE ONLY targetmetrics
    ADD CONSTRAINT target FOREIGN KEY (target) REFERENCES targets(target);


--
-- TOC entry 1950 (class 2606 OID 25719)
-- Dependencies: 1934 166 164 1960
-- Name: valid_group; Type: FK CONSTRAINT; Schema: public; Owner: grapture
--

ALTER TABLE ONLY targets
    ADD CONSTRAINT valid_group FOREIGN KEY (groupname) REFERENCES groupings(groupname) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- TOC entry 1965 (class 0 OID 0)
-- Dependencies: 6
-- Name: public; Type: ACL; Schema: -; Owner: postgres
--

REVOKE ALL ON SCHEMA public FROM PUBLIC;
REVOKE ALL ON SCHEMA public FROM postgres;
GRANT ALL ON SCHEMA public TO postgres;
GRANT ALL ON SCHEMA public TO PUBLIC;


-- Completed on 2012-11-06 06:13:37 EST

--
-- PostgreSQL database dump complete
--

