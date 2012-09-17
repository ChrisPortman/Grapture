--
-- PostgreSQL database dump
--

-- Dumped from database version 9.1.4
-- Dumped by pg_dump version 9.1.3
-- Started on 2012-09-17 09:21:29 EST

SET statement_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SET check_function_bodies = false;
SET client_min_messages = warning;

--
-- TOC entry 166 (class 3079 OID 12506)
-- Name: plpgsql; Type: EXTENSION; Schema: -; Owner: 
--

CREATE EXTENSION IF NOT EXISTS plpgsql WITH SCHEMA pg_catalog;


--
-- TOC entry 2750 (class 0 OID 0)
-- Dependencies: 166
-- Name: EXTENSION plpgsql; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION plpgsql IS 'PL/pgSQL procedural language';


SET search_path = public, pg_catalog;

SET default_tablespace = '';

SET default_with_oids = false;


-- Create grapture role
CREATE ROLE grapture WITH password 'password' LOGIN;

--
-- TOC entry 161 (class 1259 OID 16386)
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
-- TOC entry 162 (class 1259 OID 16389)
-- Dependencies: 6
-- Name: groupings; Type: TABLE; Schema: public; Owner: grapture; Tablespace: 
--

CREATE TABLE groupings (
    groupname character varying(30) NOT NULL,
    memberof character varying(50)
);


ALTER TABLE public.groupings OWNER TO grapture;

--
-- TOC entry 163 (class 1259 OID 16392)
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
-- TOC entry 164 (class 1259 OID 16398)
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
-- TOC entry 165 (class 1259 OID 16432)
-- Dependencies: 6
-- Name: users; Type: TABLE; Schema: public; Owner: grapture; Tablespace: 
--

CREATE TABLE users (
    username character varying(50) NOT NULL,
    password character varying(200) NOT NULL
);


ALTER TABLE public.users OWNER TO grapture;

--
-- TOC entry 2740 (class 0 OID 16386)
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
-- TOC entry 2741 (class 0 OID 16389)
-- Dependencies: 162
-- Data for Name: groupings; Type: TABLE DATA; Schema: public; Owner: grapture
--

COPY groupings (groupname, memberof) FROM stdin;
Unknown	\N
\.


--
-- TOC entry 2744 (class 0 OID 16432)
-- Dependencies: 165
-- Data for Name: users; Type: TABLE DATA; Schema: public; Owner: grapture
--

COPY users (username, password) FROM stdin;
admin	5f4dcc3b5aa765d61d8327deb882cf99
\.


--
-- TOC entry 2730 (class 2606 OID 16402)
-- Dependencies: 162 162
-- Name: groupings_pkey; Type: CONSTRAINT; Schema: public; Owner: grapture; Tablespace: 
--

ALTER TABLE ONLY groupings
    ADD CONSTRAINT groupings_pkey PRIMARY KEY (groupname);


--
-- TOC entry 2736 (class 2606 OID 16404)
-- Dependencies: 164 164
-- Name: target; Type: CONSTRAINT; Schema: public; Owner: grapture; Tablespace: 
--

ALTER TABLE ONLY targets
    ADD CONSTRAINT target PRIMARY KEY (target);


--
-- TOC entry 2733 (class 2606 OID 16406)
-- Dependencies: 163 163 163 163
-- Name: target_device_metric; Type: CONSTRAINT; Schema: public; Owner: grapture; Tablespace: 
--

ALTER TABLE ONLY targetmetrics
    ADD CONSTRAINT target_device_metric PRIMARY KEY (target, device, metric);


--
-- TOC entry 2738 (class 2606 OID 16436)
-- Dependencies: 165 165
-- Name: username; Type: CONSTRAINT; Schema: public; Owner: grapture; Tablespace: 
--

ALTER TABLE ONLY users
    ADD CONSTRAINT username PRIMARY KEY (username);


--
-- TOC entry 2731 (class 1259 OID 16407)
-- Dependencies: 163
-- Name: fki_target; Type: INDEX; Schema: public; Owner: grapture; Tablespace: 
--

CREATE INDEX fki_target ON targetmetrics USING btree (target);


--
-- TOC entry 2734 (class 1259 OID 16408)
-- Dependencies: 163 163
-- Name: target_devices; Type: INDEX; Schema: public; Owner: grapture; Tablespace: 
--

CREATE INDEX target_devices ON targetmetrics USING btree (target, device);


--
-- TOC entry 2739 (class 2606 OID 16409)
-- Dependencies: 2735 163 164
-- Name: target; Type: FK CONSTRAINT; Schema: public; Owner: grapture
--

ALTER TABLE ONLY targetmetrics
    ADD CONSTRAINT target FOREIGN KEY (target) REFERENCES targets(target);


--
-- TOC entry 2749 (class 0 OID 0)
-- Dependencies: 6
-- Name: public; Type: ACL; Schema: -; Owner: postgres
--

REVOKE ALL ON SCHEMA public FROM PUBLIC;
REVOKE ALL ON SCHEMA public FROM postgres;
GRANT ALL ON SCHEMA public TO postgres;
GRANT ALL ON SCHEMA public TO PUBLIC;


-- Completed on 2012-09-17 09:21:29 EST

--
-- PostgreSQL database dump complete
--

