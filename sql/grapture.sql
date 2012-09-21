--
-- PostgreSQL database dump
--

-- Dumped from database version 9.1.3
-- Dumped by pg_dump version 9.1.3
-- Started on 2012-09-21 13:59:01 EST

SET statement_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SET check_function_bodies = false;
SET client_min_messages = warning;

--
-- TOC entry 166 (class 3079 OID 11647)
-- Name: plpgsql; Type: EXTENSION; Schema: -; Owner: 
--

CREATE EXTENSION IF NOT EXISTS plpgsql WITH SCHEMA pg_catalog;


--
-- TOC entry 1896 (class 0 OID 0)
-- Dependencies: 166
-- Name: EXTENSION plpgsql; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION plpgsql IS 'PL/pgSQL procedural language';


SET search_path = public, pg_catalog;

--
-- TOC entry 179 (class 1255 OID 32843)
-- Dependencies: 6 507
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
-- TOC entry 180 (class 1255 OID 32852)
-- Dependencies: 507 6
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
-- TOC entry 181 (class 1255 OID 32856)
-- Dependencies: 6 507
-- Name: add_or_update_target_metric(character varying, character varying, character varying, character varying, integer, character varying, character varying, character varying, character varying, character varying, character varying, character varying, boolean, integer, boolean); Type: FUNCTION; Schema: public; Owner: grapture
--

CREATE FUNCTION add_or_update_target_metric(new_target character varying, new_device character varying, new_metric character varying, new_mapbase character varying, new_counterbits integer, new_module character varying, new_output character varying, new_valbase character varying, new_max character varying, new_category character varying, new_valtype character varying, new_graphgroup character varying, new_enabled boolean, new_graphorder integer, new_aggregate boolean) RETURNS integer
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
              module,  output,     valbase, max,        category,
              valtype, graphgroup, enabled, graphorder, aggregate
          )
        VALUES 
          (
              new_target,  new_device,     new_metric,  new_mapbase,    new_counterbits,
              new_module,  new_output,     new_valbase, new_max,        new_category,
              new_valtype, new_graphgroup, new_enabled, new_graphorder, new_aggregate
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
          counterbits = new_counterbits, module     = new_module,
          output      = new_output,      valbase    = new_valbase,
          max         = new_max,         category   = new_category,
          valtype     = new_valtype,     graphgroup = new_graphgroup,
          enabled     = new_enabled,     graphorder = new_graphorder,
          aggregate   = new_aggregate

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


ALTER FUNCTION public.add_or_update_target_metric(new_target character varying, new_device character varying, new_metric character varying, new_mapbase character varying, new_counterbits integer, new_module character varying, new_output character varying, new_valbase character varying, new_max character varying, new_category character varying, new_valtype character varying, new_graphgroup character varying, new_enabled boolean, new_graphorder integer, new_aggregate boolean) OWNER TO grapture;

--
-- TOC entry 178 (class 1255 OID 32853)
-- Dependencies: 6 507
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

SET default_tablespace = '';

SET default_with_oids = false;

--
-- TOC entry 161 (class 1259 OID 32807)
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
-- TOC entry 162 (class 1259 OID 32810)
-- Dependencies: 6
-- Name: groupings; Type: TABLE; Schema: public; Owner: grapture; Tablespace: 
--

CREATE TABLE groupings (
    groupname character varying(30) NOT NULL,
    memberof character varying(50)
);


ALTER TABLE public.groupings OWNER TO grapture;

--
-- TOC entry 163 (class 1259 OID 32813)
-- Dependencies: 6
-- Name: targetmetrics; Type: TABLE; Schema: public; Owner: grapture; Tablespace: 
--

CREATE TABLE targetmetrics (
    target character varying(50) NOT NULL,
    device character varying(50) NOT NULL,
    metric character varying(50) NOT NULL,
    mapbase character varying(500),
    counterbits integer,
    module character varying(50) NOT NULL,
    output character varying(50) NOT NULL,
    valbase character varying(500) NOT NULL,
    max character varying(50),
    category character varying(50),
    valtype character varying(50),
    graphgroup character varying(50),
    enabled boolean,
    graphorder integer,
    aggregate boolean
);


ALTER TABLE public.targetmetrics OWNER TO grapture;

--
-- TOC entry 164 (class 1259 OID 32819)
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
-- TOC entry 165 (class 1259 OID 32822)
-- Dependencies: 6
-- Name: users; Type: TABLE; Schema: public; Owner: grapture; Tablespace: 
--

CREATE TABLE users (
    username character varying(50) NOT NULL,
    password character varying(200) NOT NULL
);


ALTER TABLE public.users OWNER TO grapture;

--
-- TOC entry 1886 (class 0 OID 32807)
-- Dependencies: 161
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
-- TOC entry 1887 (class 0 OID 32810)
-- Dependencies: 162
-- Data for Name: groupings; Type: TABLE DATA; Schema: public; Owner: grapture
--

COPY groupings (groupname, memberof) FROM stdin;
Unknown	\N
\.


--
-- TOC entry 1890 (class 0 OID 32822)
-- Dependencies: 165
-- Data for Name: users; Type: TABLE DATA; Schema: public; Owner: grapture
--
-- DEFAULT USER/PASS
-- admin/password

COPY users (username, password) FROM stdin;
admin	5f4dcc3b5aa765d61d8327deb882cf99
\.


--
-- TOC entry 1874 (class 2606 OID 32826)
-- Dependencies: 162 162
-- Name: groupings_pkey; Type: CONSTRAINT; Schema: public; Owner: grapture; Tablespace: 
--

ALTER TABLE ONLY groupings
    ADD CONSTRAINT groupings_pkey PRIMARY KEY (groupname);


--
-- TOC entry 1881 (class 2606 OID 32828)
-- Dependencies: 164 164
-- Name: target; Type: CONSTRAINT; Schema: public; Owner: grapture; Tablespace: 
--

ALTER TABLE ONLY targets
    ADD CONSTRAINT target PRIMARY KEY (target);


--
-- TOC entry 1877 (class 2606 OID 32830)
-- Dependencies: 163 163 163 163
-- Name: target_device_metric; Type: CONSTRAINT; Schema: public; Owner: grapture; Tablespace: 
--

ALTER TABLE ONLY targetmetrics
    ADD CONSTRAINT target_device_metric PRIMARY KEY (target, device, metric);


--
-- TOC entry 1883 (class 2606 OID 32832)
-- Dependencies: 165 165
-- Name: username; Type: CONSTRAINT; Schema: public; Owner: grapture; Tablespace: 
--

ALTER TABLE ONLY users
    ADD CONSTRAINT username PRIMARY KEY (username);


--
-- TOC entry 1875 (class 1259 OID 32833)
-- Dependencies: 163
-- Name: fki_target; Type: INDEX; Schema: public; Owner: grapture; Tablespace: 
--

CREATE INDEX fki_target ON targetmetrics USING btree (target);


--
-- TOC entry 1879 (class 1259 OID 32851)
-- Dependencies: 164
-- Name: fki_valid_group; Type: INDEX; Schema: public; Owner: grapture; Tablespace: 
--

CREATE INDEX fki_valid_group ON targets USING btree (groupname);


--
-- TOC entry 1878 (class 1259 OID 32834)
-- Dependencies: 163 163
-- Name: target_devices; Type: INDEX; Schema: public; Owner: grapture; Tablespace: 
--

CREATE INDEX target_devices ON targetmetrics USING btree (target, device);


--
-- TOC entry 1884 (class 2606 OID 32835)
-- Dependencies: 163 164 1880
-- Name: target; Type: FK CONSTRAINT; Schema: public; Owner: grapture
--

ALTER TABLE ONLY targetmetrics
    ADD CONSTRAINT target FOREIGN KEY (target) REFERENCES targets(target);


--
-- TOC entry 1885 (class 2606 OID 32846)
-- Dependencies: 164 162 1873
-- Name: valid_group; Type: FK CONSTRAINT; Schema: public; Owner: grapture
--

ALTER TABLE ONLY targets
    ADD CONSTRAINT valid_group FOREIGN KEY (groupname) REFERENCES groupings(groupname) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- TOC entry 1895 (class 0 OID 0)
-- Dependencies: 6
-- Name: public; Type: ACL; Schema: -; Owner: postgres
--

REVOKE ALL ON SCHEMA public FROM PUBLIC;
REVOKE ALL ON SCHEMA public FROM postgres;
GRANT ALL ON SCHEMA public TO postgres;
GRANT ALL ON SCHEMA public TO PUBLIC;


-- Completed on 2012-09-21 13:59:01 EST

--
-- PostgreSQL database dump complete
--

