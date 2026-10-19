import request from 'supertest'
import { httpServer } from '../../server.js'
import { pool } from '../../lib/db.js'

const agent = request.agent(httpServer)

describe('🏥 Health Endpoints', () => {
  afterAll(async () => {
    await pool.end()
    httpServer.close()
  })

  describe('GET /health', () => {
    it('✅ Liveness probe debe responder 200 con status ok', async () => {
      const res = await agent.get('/health')

      expect(res.statusCode).toBe(200)
      expect(res.body.status).toBe('ok')
      expect(res.body.message).toBeDefined()
    })
  })

  describe('GET /health/db', () => {
    it('✅ Readiness probe debe responder 200 cuando la BD está disponible', async () => {
      const res = await agent.get('/health/db')

      expect(res.statusCode).toBe(200)
      expect(res.body.status).toBe('ok')
      expect(res.body.message).toMatch(/healthy/i)
    })
  })

  describe('GET /', () => {
    it('✅ Ruta raíz debe retornar info del proyecto', async () => {
      const res = await agent.get('/')

      expect(res.statusCode).toBe(200)
      expect(res.body.version).toBeDefined()
      expect(res.body.environment).toBeDefined()
    })
  })
})
