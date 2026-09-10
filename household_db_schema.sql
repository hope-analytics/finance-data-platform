--
-- PostgreSQL database dump
--

\restrict gsOU49Kg3DUsi28nIBePWQ07jjmRBfTfQollceey8CytmvKwYGyZlhYrtM5S1tk

-- Dumped from database version 18.6 (Homebrew)
-- Dumped by pg_dump version 18.6 (Homebrew)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: transactions; Type: TABLE; Schema: public; Owner: dbadmin
--

CREATE TABLE public.transactions (
    expense_id bigint NOT NULL,
    transaction_date date NOT NULL,
    merchant character varying(150) NOT NULL,
    description text,
    amount numeric(12,2) NOT NULL,
    category character varying(100),
    payment_source character varying(50) NOT NULL,
    notes text,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


ALTER TABLE public.transactions OWNER TO dbadmin;

--
-- Name: transactions_expense_id_seq; Type: SEQUENCE; Schema: public; Owner: dbadmin
--

ALTER TABLE public.transactions ALTER COLUMN expense_id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.transactions_expense_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: transactions transactions_pkey; Type: CONSTRAINT; Schema: public; Owner: dbadmin
--

ALTER TABLE ONLY public.transactions
    ADD CONSTRAINT transactions_pkey PRIMARY KEY (expense_id);


--
-- Name: SCHEMA public; Type: ACL; Schema: -; Owner: pg_database_owner
--

GRANT USAGE ON SCHEMA public TO expense_app;


--
-- Name: TABLE transactions; Type: ACL; Schema: public; Owner: dbadmin
--

GRANT SELECT,INSERT ON TABLE public.transactions TO expense_app;


--
-- Name: SEQUENCE transactions_expense_id_seq; Type: ACL; Schema: public; Owner: dbadmin
--

GRANT SELECT,USAGE ON SEQUENCE public.transactions_expense_id_seq TO expense_app;


--
-- PostgreSQL database dump complete
--

\unrestrict gsOU49Kg3DUsi28nIBePWQ07jjmRBfTfQollceey8CytmvKwYGyZlhYrtM5S1tk

