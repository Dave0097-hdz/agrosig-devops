import express from 'express'
import { pool } from '../../lib/db.js'

const router = express.Router()

/**
 * GET /health
 * Liveness probe: verifica que el proceso está vivo.
 */
router.get('/', (req, res) => {
    res.status(200).json({ status: 'ok', message: 'Server is running' })
})

/**
 * GET /health/db
 * Readiness probe: verifica que la conexión a la base de datos funciona.
 */
router.get('/db', async (req, res) => {
    try {
        await pool.query('SELECT 1')
        res.status(200).json({ status: 'ok', message: 'Database connection is healthy' })
    } catch (error) {
        res.status(500).json({ status: 'error', message: 'Database connection failed', error: error.message })
    }
})

export default router
