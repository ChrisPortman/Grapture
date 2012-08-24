--
-- PostgreSQL database dump
--

-- Dumped from database version 9.1.3
-- Dumped by pg_dump version 9.1.3
-- Started on 2012-08-09 10:23:04 EST

SET statement_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SET check_function_bodies = false;
SET client_min_messages = warning;

--
-- TOC entry 1881 (class 1262 OID 16484)
-- Name: grasshopper; Type: DATABASE; Schema: -; Owner: grasshopper
--

CREATE USER grasshopper WITH PASSWORD 'hoppergrass';
CREATE DATABASE grasshopper WITH TEMPLATE = template0 ENCODING = 'UTF8' LC_COLLATE = 'en_AU.UTF-8' LC_CTYPE = 'en_AU.UTF-8';


ALTER DATABASE grasshopper OWNER TO grasshopper;

\connect grasshopper

SET statement_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SET check_function_bodies = false;
SET client_min_messages = warning;

--
-- TOC entry 165 (class 3079 OID 11647)
-- Name: plpgsql; Type: EXTENSION; Schema: -; Owner: 
--

CREATE EXTENSION IF NOT EXISTS plpgsql WITH SCHEMA pg_catalog;


--
-- TOC entry 1884 (class 0 OID 0)
-- Dependencies: 165
-- Name: EXTENSION plpgsql; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION plpgsql IS 'PL/pgSQL procedural language';


SET search_path = public, pg_catalog;

SET default_tablespace = '';

SET default_with_oids = false;

--
-- TOC entry 164 (class 1259 OID 24612)
-- Dependencies: 6
-- Name: graphgroupsettings; Type: TABLE; Schema: public; Owner: grasshopper; Tablespace: 
--

CREATE TABLE graphgroupsettings (
    graphgroup character varying(50),
    fill boolean,
    stack boolean,
    mirror boolean,
    percent boolean
);


ALTER TABLE public.graphgroupsettings OWNER TO grasshopper;

--
-- TOC entry 163 (class 1259 OID 24607)
-- Dependencies: 6
-- Name: groupings; Type: TABLE; Schema: public; Owner: grasshopper; Tablespace: 
--

CREATE TABLE groupings (
    groupname character varying(30) NOT NULL,
    memberof character varying(50)
);


ALTER TABLE public.groupings OWNER TO grasshopper;

--
-- TOC entry 162 (class 1259 OID 16615)
-- Dependencies: 6
-- Name: targetmetrics; Type: TABLE; Schema: public; Owner: grasshopper; Tablespace: 
--

CREATE TABLE targetmetrics (
    target character varying(50) NOT NULL,
    device character varying(50) NOT NULL,
    metric character varying(50) NOT NULL,
    mapbase character varying(50),
    counterbits integer,
    module character varying(50) NOT NULL,
    output character varying(50) NOT NULL,
    valbase character varying(50) NOT NULL,
    max character varying(50),
    category character varying(50),
    valtype character varying(50),
    graphgroup character varying(50),
    enabled boolean,
    graphorder integer
);


ALTER TABLE public.targetmetrics OWNER TO grasshopper;

--
-- TOC entry 161 (class 1259 OID 16610)
-- Dependencies: 6
-- Name: targets; Type: TABLE; Schema: public; Owner: grasshopper; Tablespace: 
--

CREATE TABLE targets (
    target character varying(50) NOT NULL,
    snmpversion integer NOT NULL,
    snmpcommunity character varying(50) NOT NULL,
    lastdiscovered timestamp without time zone,
    graphitetreeloc character varying(50),
    groupname character varying(50)
);


ALTER TABLE public.targets OWNER TO grasshopper;

--
-- TOC entry 1878 (class 0 OID 24612)
-- Dependencies: 164
-- Data for Name: graphgroupsettings; Type: TABLE DATA; Schema: public; Owner: grasshopper
--

COPY graphgroupsettings (graphgroup, fill, stack, mirror, percent) FROM stdin;
InterfaceTraffic	t	f	t	\N
InterfaceErrors	t	f	t	\N
MemoryUsage	t	t	f	\N
StorageIOBytes	t	f	t	\N
StorageIOCount	t	f	t	\N
CPUUsage	t	t	f	\N
SpaceUsed	t	f	f	t
\.


--
-- TOC entry 1877 (class 0 OID 24607)
-- Dependencies: 163
-- Data for Name: groupings; Type: TABLE DATA; Schema: public; Owner: grasshopper
--

COPY groupings (groupname, memberof) FROM stdin;
Servers	\N
Linux	Servers
Network	\N
Routers	Network
Mail Servers	Linux
Unknown	\N
\.

--
-- TOC entry 1873 (class 2606 OID 24611)
-- Dependencies: 163 163
-- Name: groupings_pkey; Type: CONSTRAINT; Schema: public; Owner: grasshopper; Tablespace: 
--

ALTER TABLE ONLY groupings
    ADD CONSTRAINT groupings_pkey PRIMARY KEY (groupname);


--
-- TOC entry 1867 (class 2606 OID 16614)
-- Dependencies: 161 161
-- Name: target; Type: CONSTRAINT; Schema: public; Owner: grasshopper; Tablespace: 
--

ALTER TABLE ONLY targets
    ADD CONSTRAINT target PRIMARY KEY (target);


--
-- TOC entry 1870 (class 2606 OID 16619)
-- Dependencies: 162 162 162 162
-- Name: target_device_metric; Type: CONSTRAINT; Schema: public; Owner: grasshopper; Tablespace: 
--

ALTER TABLE ONLY targetmetrics
    ADD CONSTRAINT target_device_metric PRIMARY KEY (target, device, metric);


--
-- TOC entry 1868 (class 1259 OID 16625)
-- Dependencies: 162
-- Name: fki_target; Type: INDEX; Schema: public; Owner: grasshopper; Tablespace: 
--

CREATE INDEX fki_target ON targetmetrics USING btree (target);


--
-- TOC entry 1871 (class 1259 OID 24606)
-- Dependencies: 162 162
-- Name: target_devices; Type: INDEX; Schema: public; Owner: grasshopper; Tablespace: 
--

CREATE INDEX target_devices ON targetmetrics USING btree (target, device);


--
-- TOC entry 1874 (class 2606 OID 16620)
-- Dependencies: 161 1866 162
-- Name: target; Type: FK CONSTRAINT; Schema: public; Owner: grasshopper
--

ALTER TABLE ONLY targetmetrics
    ADD CONSTRAINT target FOREIGN KEY (target) REFERENCES targets(target);


--
-- TOC entry 1883 (class 0 OID 0)
-- Dependencies: 6
-- Name: public; Type: ACL; Schema: -; Owner: postgres
--

REVOKE ALL ON SCHEMA public FROM PUBLIC;
REVOKE ALL ON SCHEMA public FROM postgres;
GRANT ALL ON SCHEMA public TO postgres;
GRANT ALL ON SCHEMA public TO PUBLIC;


-- Completed on 2012-08-09 10:23:04 EST

--
-- PostgreSQL database dump complete
--
