-- Las dos bases del reparto, para el Postgres de PRUEBAS de docker-compose.
--
-- Este fichero sólo lo lee la imagen de postgres la PRIMERA vez que se crea el volumen.
-- En el VPS no se usa: allí hay un solo Postgres para toda la casa y las bases se crean
-- a mano dentro de él (docs/DOKPLOY-NUEVO-PROYECTO.md, Parte 4).
--
-- SON DOS BASES Y NO UNA. El sincronizador no guarda datos del reparto: guarda la
-- contabilidad de la sincronización, con su propia serie de migraciones y sin una sola
-- clave ajena hacia la otra (sync/db/migrations/00001_sync.sql lo explica). Meterlas
-- juntas es invitar a que alguien escriba ese JOIN que no se puede escribir.

-- `reparto` ya la crea la imagen con POSTGRES_DB. Aquí sólo falta la del sincronizador.
CREATE DATABASE reparto_sync OWNER reparto;
