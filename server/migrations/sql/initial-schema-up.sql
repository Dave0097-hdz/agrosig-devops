--
-- PostgreSQL database dump
--

-- Dumped from database version 17.4
-- Dumped by pg_dump version 17.4

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: tiger; Type: SCHEMA; Schema: -; Owner: postgres
--




--
-- Name: tiger_data; Type: SCHEMA; Schema: -; Owner: postgres
--




--
-- Name: topology; Type: SCHEMA; Schema: -; Owner: postgres
--




--
--



--
-- Name: postgis; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS postgis WITH SCHEMA public;


--
-- Name: EXTENSION postgis; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION postgis IS 'PostGIS geometry and geography spatial types and functions';


--
-- Name: register_user_plot(integer, character varying, text, numeric, text); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.register_user_plot(IN p_user_id integer, IN p_plot_name character varying, IN p_location text, IN p_area numeric, IN p_coordinates text)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_lat DOUBLE PRECISION;
    v_long DOUBLE PRECISION;
    v_lat_str TEXT;
    v_long_str TEXT;
    v_user_exists BOOLEAN;
BEGIN
    -- Verificar si el usuario existe
    SELECT EXISTS(SELECT 1 FROM users WHERE user_id = p_user_id) INTO v_user_exists;

    IF NOT v_user_exists THEN 
        RAISE EXCEPTION 'User with ID % does not exist', p_user_id;
    END IF;
    
    -- Verificar si el usuario ya tiene una parcela
    IF EXISTS (SELECT 1 FROM plots WHERE user_id = p_user_id) THEN
        RAISE EXCEPTION 'User already has a plot';
    END IF;
    
    -- Extraer partes de las coordenadas
    v_lat_str := SPLIT_PART(p_coordinates, ',', 1);
    v_long_str := SPLIT_PART(p_coordinates, ',', 2);
    
    -- Limpiar coordenadas (remover puntos adicionales)
    v_lat_str := REPLACE(v_lat_str, '..', '.');
    v_long_str := REPLACE(v_long_str, '..', '.');
    
    -- Convertir a números
    BEGIN
        v_lat := CAST(v_lat_str AS DOUBLE PRECISION);
        v_long := CAST(v_long_str AS DOUBLE PRECISION);
    EXCEPTION WHEN OTHERS THEN
        RAISE EXCEPTION 'Invalid coordinates format: %', p_coordinates;
    END;
    
    -- Validar rangos geográficos
    IF v_lat < -90 OR v_lat > 90 OR v_long < -180 OR v_long > 180 THEN
        RAISE EXCEPTION 'Coordinates out of range: Latitude (-90 to 90), Longitude (-180 to 180)';
    END IF;
    
    -- Validar que el área sea positiva
    IF p_area <= 0 THEN
        RAISE EXCEPTION 'Area must be a positive number';
    END IF;
    
    -- Insertar la parcela
    INSERT INTO plots (
        user_id, 
        plot_name, 
        location, 
        area, 
        geom, 
        is_active
    ) VALUES (
        p_user_id, 
        p_plot_name, 
        p_location, 
        p_area, 
        ST_SetSRID(ST_MakePoint(v_long, v_lat), 4326),
        TRUE
    );
    
    -- Actualizar estado del usuario
    UPDATE users SET configured_plot = TRUE WHERE user_id = p_user_id;
END;
$$;



--
-- Name: soft_delete_user_crop(integer, integer); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.soft_delete_user_crop(IN c_user_id integer, IN c_crop_id integer)
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- Verificar y desactivar en una sola operación
    UPDATE crop SET is_active = FALSE 
    WHERE crop_id = c_crop_id 
      AND user_id = c_user_id
      AND is_active = TRUE;
    
    IF NOT FOUND THEN
        RAISE EXCEPTION 'El cultivo no existe, no pertenece al usuario o ya está inactivo';
    END IF;
    
    -- NOTA: Eliminé la línea que actualizaba 'cro' porque esa tabla no existe
    -- Si necesitas actualizar algo relacionado, debería ser en 'users' o 'plots'
END;
$$;



--
-- Name: soft_delete_user_plot(integer, integer); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.soft_delete_user_plot(IN p_user_id integer, IN p_plot_id integer)
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- Verificar y desactivar en una sola operación
    UPDATE plots SET is_active = FALSE 
    WHERE plot_id = p_plot_id 
      AND user_id = p_user_id
      AND is_active = TRUE;
    
    IF NOT FOUND THEN
        RAISE EXCEPTION 'La parcela no existe, no pertenece al usuario o ya está inactiva';
    END IF;
    
    -- Actualizar estado del usuario
    UPDATE users SET configured_plot = FALSE WHERE user_id = p_user_id;
END;
$$;



--
-- Name: update_user_plot(integer, integer, character varying, text, numeric, text); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.update_user_plot(IN p_user_id integer, IN p_plot_id integer, IN p_plot_name character varying, IN p_location text, IN p_area numeric, IN p_coordinates text)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_lat DOUBLE PRECISION;
    v_long DOUBLE PRECISION;
    v_lat_str TEXT;
    v_long_str TEXT;
    v_plot_exists BOOLEAN;
BEGIN
    -- Verificar que el plot existe y pertenece al usuario
    SELECT EXISTS(
        SELECT 1 FROM plots 
        WHERE plot_id = p_plot_id AND user_id = p_user_id AND is_active = true
    ) INTO v_plot_exists;

    IF NOT v_plot_exists THEN
        RAISE EXCEPTION 'Plot not found, inactive, or does not belong to user';
    END IF;

    -- Extraer y limpiar coordenadas
    v_lat_str := SPLIT_PART(p_coordinates, ',', 1);
    v_long_str := SPLIT_PART(p_coordinates, ',', 2);
    
    v_lat_str := REPLACE(v_lat_str, '..', '.');
    v_long_str := REPLACE(v_long_str, '..', '.');
    
    -- Convertir a números
    BEGIN
        v_lat := CAST(v_lat_str AS DOUBLE PRECISION);
        v_long := CAST(v_long_str AS DOUBLE PRECISION);
    EXCEPTION WHEN OTHERS THEN
        RAISE EXCEPTION 'Invalid coordinates format: %', p_coordinates;
    END;
    
    -- Validar rangos geográficos
    IF v_lat < -90 OR v_lat > 90 THEN
        RAISE EXCEPTION 'Latitude out of range (-90 to 90): %', v_lat;
    END IF;
    
    IF v_long < -180 OR v_long > 180 THEN
        RAISE EXCEPTION 'Longitude out of range (-180 to 180): %', v_long;
    END IF;
    
    -- Validar área
    IF p_area <= 0 THEN
        RAISE EXCEPTION 'Area must be a positive number';
    END IF;
    
    -- Actualizar la parcela
    UPDATE plots SET 
        plot_name = p_plot_name,
        location = p_location,
        area = p_area,
        geom = ST_SetSRID(ST_MakePoint(v_long, v_lat), 4326),
        updated_at = CURRENT_TIMESTAMP
    WHERE plot_id = p_plot_id AND user_id = p_user_id;
    
    -- Verificar que se actualizó
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Failed to update plot';
    END IF;
END;
$$;



SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: activity; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.activity (
    activity_id integer NOT NULL,
    crop_id integer NOT NULL,
    user_id integer NOT NULL,
    activity_type text NOT NULL,
    date date DEFAULT CURRENT_DATE NOT NULL,
    description text,
    cost_total numeric DEFAULT 0,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);



--
-- Name: activity_activity_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.activity_activity_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;



--
-- Name: activity_activity_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.activity_activity_id_seq OWNED BY public.activity.activity_id;


--
-- Name: activity_branch; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.activity_branch (
    branch_id integer NOT NULL,
    production_id integer NOT NULL,
    activity_id integer NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);



--
-- Name: activity_branch_branch_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.activity_branch_branch_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;



--
-- Name: activity_branch_branch_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.activity_branch_branch_id_seq OWNED BY public.activity_branch.branch_id;


--
-- Name: comments; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.comments (
    comment_id integer NOT NULL,
    user_id integer NOT NULL,
    message text NOT NULL,
    is_edited boolean DEFAULT false,
    is_deleted boolean DEFAULT false,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);



--
-- Name: comments_comment_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.comments_comment_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;



--
-- Name: comments_comment_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.comments_comment_id_seq OWNED BY public.comments.comment_id;


--
-- Name: crop; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.crop (
    crop_id integer NOT NULL,
    user_id integer NOT NULL,
    plot_id integer NOT NULL,
    crop_type text NOT NULL,
    crop_variety text,
    planting_date date,
    harvest_date date,
    is_active boolean DEFAULT true,
    cost_total numeric DEFAULT 0,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);



--
-- Name: crop_crop_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.crop_crop_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;



--
-- Name: crop_crop_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.crop_crop_id_seq OWNED BY public.crop.crop_id;


--
-- Name: input_used; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.input_used (
    input_id integer NOT NULL,
    activity_id integer NOT NULL,
    input_name character varying(255) NOT NULL,
    unit text NOT NULL,
    quantity numeric DEFAULT 0,
    unit_cost numeric DEFAULT 0,
    cost_unit text NOT NULL,
    base_unit text NOT NULL,
    conversion_factor numeric DEFAULT 1,
    cost_total numeric GENERATED ALWAYS AS (((quantity * unit_cost) * conversion_factor)) STORED,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);



--
-- Name: input_used_input_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.input_used_input_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;



--
-- Name: input_used_input_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.input_used_input_id_seq OWNED BY public.input_used.input_id;


--
-- Name: notifications; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.notifications (
    notification_id integer NOT NULL,
    user_id integer NOT NULL,
    type_notification character varying(255),
    title_notification character varying(255),
    message_notification text,
    status_notification text,
    link_notification text,
    sent_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    is_read boolean DEFAULT false,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);



--
-- Name: notifications_notification_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.notifications_notification_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;



--
-- Name: notifications_notification_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.notifications_notification_id_seq OWNED BY public.notifications.notification_id;


--
-- Name: plot_climate; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.plot_climate (
    climate_id integer NOT NULL,
    plot_id integer NOT NULL,
    temperature numeric,
    humidity numeric,
    description text,
    precipitation numeric,
    wind_speed numeric,
    atmospheric_pressure numeric,
    wind_direction numeric,
    min_temp numeric,
    max_temp numeric,
    city_name character varying(255),
    date date NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);



--
-- Name: plot_climate_climate_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.plot_climate_climate_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;



--
-- Name: plot_climate_climate_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.plot_climate_climate_id_seq OWNED BY public.plot_climate.climate_id;


--
-- Name: plots; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.plots (
    plot_id integer NOT NULL,
    user_id integer NOT NULL,
    plot_name character varying(255),
    location text,
    area numeric,
    geom public.geometry(Point,4326),
    is_active boolean DEFAULT true,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);



--
-- Name: plots_plot_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.plots_plot_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;



--
-- Name: plots_plot_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.plots_plot_id_seq OWNED BY public.plots.plot_id;


--
-- Name: production_batch; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.production_batch (
    production_id integer NOT NULL,
    crop_id integer NOT NULL,
    name text,
    unique_code text,
    creation_date date,
    is_active boolean DEFAULT true,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);



--
-- Name: production_batch_production_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.production_batch_production_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;



--
-- Name: production_batch_production_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.production_batch_production_id_seq OWNED BY public.production_batch.production_id;


--
-- Name: qr_lote; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.qr_lote (
    qr_id integer NOT NULL,
    production_id integer,
    qr_code text,
    qr_data jsonb,
    generation_date timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);



--
-- Name: qr_lote_qr_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.qr_lote_qr_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;



--
-- Name: qr_lote_qr_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.qr_lote_qr_id_seq OWNED BY public.qr_lote.qr_id;


--
-- Name: role; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.role (
    role_id integer NOT NULL,
    name character varying(255),
    description text,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);



--
-- Name: role_role_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.role_role_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;



--
-- Name: role_role_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.role_role_id_seq OWNED BY public.role.role_id;


--
-- Name: tokens; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.tokens (
    token_id integer NOT NULL,
    user_id integer NOT NULL,
    refresh_token text NOT NULL,
    is_revoked boolean DEFAULT false,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);



--
-- Name: tokens_token_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.tokens_token_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;



--
-- Name: tokens_token_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.tokens_token_id_seq OWNED BY public.tokens.token_id;


--
-- Name: user_fcm_tokens; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.user_fcm_tokens (
    token_id integer NOT NULL,
    user_id integer NOT NULL,
    fcm_token text NOT NULL,
    device_type character varying(50),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);



--
-- Name: user_fcm_tokens_token_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.user_fcm_tokens_token_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;



--
-- Name: user_fcm_tokens_token_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.user_fcm_tokens_token_id_seq OWNED BY public.user_fcm_tokens.token_id;


--
-- Name: users; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.users (
    user_id integer NOT NULL,
    google_id text,
    role_id integer NOT NULL,
    first_name character varying(255),
    paternal_surname character varying(255),
    maternal_surname character varying(255),
    email character varying(255) NOT NULL,
    password text NOT NULL,
    image_user text,
    configured_plot boolean DEFAULT false,
    is_active boolean,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP
);



--
-- Name: users_user_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.users_user_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;



--
-- Name: users_user_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.users_user_id_seq OWNED BY public.users.user_id;


--
-- Name: activity activity_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.activity ALTER COLUMN activity_id SET DEFAULT nextval('public.activity_activity_id_seq'::regclass);


--
-- Name: activity_branch branch_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.activity_branch ALTER COLUMN branch_id SET DEFAULT nextval('public.activity_branch_branch_id_seq'::regclass);


--
-- Name: comments comment_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.comments ALTER COLUMN comment_id SET DEFAULT nextval('public.comments_comment_id_seq'::regclass);


--
-- Name: crop crop_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.crop ALTER COLUMN crop_id SET DEFAULT nextval('public.crop_crop_id_seq'::regclass);


--
-- Name: input_used input_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.input_used ALTER COLUMN input_id SET DEFAULT nextval('public.input_used_input_id_seq'::regclass);


--
-- Name: notifications notification_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.notifications ALTER COLUMN notification_id SET DEFAULT nextval('public.notifications_notification_id_seq'::regclass);


--
-- Name: plot_climate climate_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.plot_climate ALTER COLUMN climate_id SET DEFAULT nextval('public.plot_climate_climate_id_seq'::regclass);


--
-- Name: plots plot_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.plots ALTER COLUMN plot_id SET DEFAULT nextval('public.plots_plot_id_seq'::regclass);


--
-- Name: production_batch production_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.production_batch ALTER COLUMN production_id SET DEFAULT nextval('public.production_batch_production_id_seq'::regclass);


--
-- Name: qr_lote qr_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.qr_lote ALTER COLUMN qr_id SET DEFAULT nextval('public.qr_lote_qr_id_seq'::regclass);


--
-- Name: role role_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.role ALTER COLUMN role_id SET DEFAULT nextval('public.role_role_id_seq'::regclass);


--
-- Name: tokens token_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.tokens ALTER COLUMN token_id SET DEFAULT nextval('public.tokens_token_id_seq'::regclass);


--
-- Name: user_fcm_tokens token_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_fcm_tokens ALTER COLUMN token_id SET DEFAULT nextval('public.user_fcm_tokens_token_id_seq'::regclass);


--
-- Name: users user_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.users ALTER COLUMN user_id SET DEFAULT nextval('public.users_user_id_seq'::regclass);


--
-- Data for Name: activity; Type: TABLE DATA; Schema: public; Owner: postgres
--



--
-- Data for Name: activity_branch; Type: TABLE DATA; Schema: public; Owner: postgres
--



--
-- Data for Name: comments; Type: TABLE DATA; Schema: public; Owner: postgres
--



--
-- Data for Name: crop; Type: TABLE DATA; Schema: public; Owner: postgres
--



--
-- Data for Name: input_used; Type: TABLE DATA; Schema: public; Owner: postgres
--



--
-- Data for Name: notifications; Type: TABLE DATA; Schema: public; Owner: postgres
--



--
-- Data for Name: plot_climate; Type: TABLE DATA; Schema: public; Owner: postgres
--



--
-- Data for Name: plots; Type: TABLE DATA; Schema: public; Owner: postgres
--



--
-- Data for Name: pointcloud_formats; Type: TABLE DATA; Schema: public; Owner: postgres
--



--
-- Data for Name: production_batch; Type: TABLE DATA; Schema: public; Owner: postgres
--



--
-- Data for Name: qr_lote; Type: TABLE DATA; Schema: public; Owner: postgres
--



--
-- Data for Name: role; Type: TABLE DATA; Schema: public; Owner: postgres
--



--
-- Data for Name: spatial_ref_sys; Type: TABLE DATA; Schema: public; Owner: postgres
--



--
-- Data for Name: tokens; Type: TABLE DATA; Schema: public; Owner: postgres
--



--
-- Data for Name: us_gaz; Type: TABLE DATA; Schema: public; Owner: postgres
--



--
-- Data for Name: us_lex; Type: TABLE DATA; Schema: public; Owner: postgres
--



--
-- Data for Name: us_rules; Type: TABLE DATA; Schema: public; Owner: postgres
--



--
-- Data for Name: user_fcm_tokens; Type: TABLE DATA; Schema: public; Owner: postgres
--



--
-- Data for Name: users; Type: TABLE DATA; Schema: public; Owner: postgres
--



--
-- Data for Name: geocode_settings; Type: TABLE DATA; Schema: tiger; Owner: postgres
--



--
-- Data for Name: pagc_gaz; Type: TABLE DATA; Schema: tiger; Owner: postgres
--



--
-- Data for Name: pagc_lex; Type: TABLE DATA; Schema: tiger; Owner: postgres
--



--
-- Data for Name: pagc_rules; Type: TABLE DATA; Schema: tiger; Owner: postgres
--



--
-- Data for Name: topology; Type: TABLE DATA; Schema: topology; Owner: postgres
--



--
-- Data for Name: layer; Type: TABLE DATA; Schema: topology; Owner: postgres
--



--
-- Name: activity_activity_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--



--
-- Name: activity_branch_branch_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--



--
-- Name: comments_comment_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--



--
-- Name: crop_crop_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--



--
-- Name: input_used_input_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--



--
-- Name: notifications_notification_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--



--
-- Name: plot_climate_climate_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--



--
-- Name: plots_plot_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--



--
-- Name: production_batch_production_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--



--
-- Name: qr_lote_qr_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--



--
-- Name: role_role_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--



--
-- Name: tokens_token_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--



--
-- Name: user_fcm_tokens_token_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--



--
-- Name: users_user_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--



--
-- Name: topology_id_seq; Type: SEQUENCE SET; Schema: topology; Owner: postgres
--



--
-- Name: activity_branch activity_branch_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.activity_branch
    ADD CONSTRAINT activity_branch_pkey PRIMARY KEY (branch_id);


--
-- Name: activity activity_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.activity
    ADD CONSTRAINT activity_pkey PRIMARY KEY (activity_id);


--
-- Name: comments comments_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.comments
    ADD CONSTRAINT comments_pkey PRIMARY KEY (comment_id);


--
-- Name: crop crop_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.crop
    ADD CONSTRAINT crop_pkey PRIMARY KEY (crop_id);


--
-- Name: input_used input_used_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.input_used
    ADD CONSTRAINT input_used_pkey PRIMARY KEY (input_id);


--
-- Name: notifications notifications_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.notifications
    ADD CONSTRAINT notifications_pkey PRIMARY KEY (notification_id);


--
-- Name: plot_climate plot_climate_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.plot_climate
    ADD CONSTRAINT plot_climate_pkey PRIMARY KEY (climate_id);


--
-- Name: plots plots_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.plots
    ADD CONSTRAINT plots_pkey PRIMARY KEY (plot_id);


--
-- Name: production_batch production_batch_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.production_batch
    ADD CONSTRAINT production_batch_pkey PRIMARY KEY (production_id);


--
-- Name: production_batch production_batch_unique_code_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.production_batch
    ADD CONSTRAINT production_batch_unique_code_key UNIQUE (unique_code);


--
-- Name: qr_lote qr_lote_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.qr_lote
    ADD CONSTRAINT qr_lote_pkey PRIMARY KEY (qr_id);


--
-- Name: role role_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.role
    ADD CONSTRAINT role_pkey PRIMARY KEY (role_id);


--
-- Name: tokens tokens_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.tokens
    ADD CONSTRAINT tokens_pkey PRIMARY KEY (token_id);


--
-- Name: plot_climate unique_plot_date; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.plot_climate
    ADD CONSTRAINT unique_plot_date UNIQUE (plot_id, date);


--
-- Name: user_fcm_tokens unique_user_token; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_fcm_tokens
    ADD CONSTRAINT unique_user_token UNIQUE (user_id, fcm_token);


--
-- Name: user_fcm_tokens user_fcm_tokens_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_fcm_tokens
    ADD CONSTRAINT user_fcm_tokens_pkey PRIMARY KEY (token_id);


--
-- Name: users users_email_unique; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_email_unique UNIQUE (email);


--
-- Name: users users_google_id_unique; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_google_id_unique UNIQUE (google_id);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (user_id);


--
-- Name: activity_branch activity_branch_activity_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.activity_branch
    ADD CONSTRAINT activity_branch_activity_id_fkey FOREIGN KEY (activity_id) REFERENCES public.activity(activity_id);


--
-- Name: activity_branch activity_branch_production_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.activity_branch
    ADD CONSTRAINT activity_branch_production_id_fkey FOREIGN KEY (production_id) REFERENCES public.production_batch(production_id);


--
-- Name: activity activity_crop_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.activity
    ADD CONSTRAINT activity_crop_id_fkey FOREIGN KEY (crop_id) REFERENCES public.crop(crop_id) ON DELETE CASCADE;


--
-- Name: activity activity_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.activity
    ADD CONSTRAINT activity_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(user_id) ON DELETE CASCADE;


--
-- Name: comments comments_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.comments
    ADD CONSTRAINT comments_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(user_id);


--
-- Name: crop crop_plot_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.crop
    ADD CONSTRAINT crop_plot_id_fkey FOREIGN KEY (plot_id) REFERENCES public.plots(plot_id) ON DELETE CASCADE;


--
-- Name: crop crop_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.crop
    ADD CONSTRAINT crop_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(user_id) ON DELETE CASCADE;


--
-- Name: input_used input_used_activity_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.input_used
    ADD CONSTRAINT input_used_activity_id_fkey FOREIGN KEY (activity_id) REFERENCES public.activity(activity_id) ON DELETE CASCADE;


--
-- Name: notifications notifications_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.notifications
    ADD CONSTRAINT notifications_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(user_id);


--
-- Name: plot_climate plot_climate_plot_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.plot_climate
    ADD CONSTRAINT plot_climate_plot_id_fkey FOREIGN KEY (plot_id) REFERENCES public.plots(plot_id);


--
-- Name: plots plots_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.plots
    ADD CONSTRAINT plots_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(user_id);


--
-- Name: production_batch production_batch_crop_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.production_batch
    ADD CONSTRAINT production_batch_crop_id_fkey FOREIGN KEY (crop_id) REFERENCES public.crop(crop_id);


--
-- Name: qr_lote qr_lote_production_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.qr_lote
    ADD CONSTRAINT qr_lote_production_id_fkey FOREIGN KEY (production_id) REFERENCES public.production_batch(production_id);


--
-- Name: tokens tokens_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.tokens
    ADD CONSTRAINT tokens_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(user_id) ON DELETE CASCADE;


--
-- Name: user_fcm_tokens user_fcm_tokens_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_fcm_tokens
    ADD CONSTRAINT user_fcm_tokens_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(user_id) ON DELETE CASCADE;


--
-- PostgreSQL database dump complete
--

