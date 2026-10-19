import request from 'supertest'
import { httpServer } from '../../server.js'
import { pool } from '../../lib/db.js'

const agent = request.agent(httpServer)

describe('🔐 AUTH Endpoints', () => {
  beforeAll(async () => {
    await pool.query("DELETE FROM users WHERE email LIKE '%test%'")
  })

  afterAll(async () => {
    await pool.query("DELETE FROM users WHERE email LIKE '%test%'")
    await pool.end()
    httpServer.close()
  })

  describe('🧩 POST /auth/register', () => {
    it('✅ Debe registrar un nuevo usuario exitosamente', async () => {
      const res = await agent.post('/auth/register').send({
        first_name: 'David',
        paternal_surname: 'Hernandez',
        maternal_surname: 'Chavarria',
        email: 'david.test@example.com',
        password: 'password123'
      })

      expect(res.statusCode).toBe(201)
      expect(res.body.success).toBe(true)
      expect(res.body.data.email).toBe('david.test@example.com')
      expect(res.body.token).toBeDefined()
    })

    it('🚫 No debe permitir registrar un correo ya existente', async () => {
      const res = await agent.post('/auth/register').send({
        first_name: 'David',
        paternal_surname: 'Hernandez',
        maternal_surname: 'Chavarria',
        email: 'david.test@example.com',
        password: 'password123'
      })

      expect(res.statusCode).toBeGreaterThanOrEqual(400)
      expect(res.body.success).toBe(false)
    })

    it('🚫 No debe registrar sin campos requeridos', async () => {
      const res = await agent.post('/auth/register').send({
        email: 'incompleto.test@example.com'
      })

      expect(res.statusCode).toBeGreaterThanOrEqual(400)
    })
  })

  describe('🔑 POST /auth/login', () => {
    it('✅ Debe iniciar sesión con credenciales válidas', async () => {
      const res = await agent.post('/auth/login').send({
        email: 'david.test@example.com',
        password: 'password123'
      })

      expect(res.statusCode).toBe(200)
      expect(res.body.success).toBe(true)
      expect(res.body.data.token).toBeDefined()
      expect(res.body.data.user.email).toBe('david.test@example.com')
    })

    it('🚫 No debe iniciar sesión con contraseña incorrecta', async () => {
      const res = await agent.post('/auth/login').send({
        email: 'david.test@example.com',
        password: 'wrongpassword'
      })

      expect(res.statusCode).toBeGreaterThanOrEqual(400)
      expect(res.body.success).toBe(false)
    })

    it('🚫 No debe iniciar sesión con usuario no registrado', async () => {
      const res = await agent.post('/auth/login').send({
        email: 'noexiste.test@example.com',
        password: 'password123'
      })

      expect(res.statusCode).toBeGreaterThanOrEqual(400)
      expect(res.body.success).toBe(false)
    })
  })

  describe('🚪 POST /auth/logout', () => {
    it('🚫 No debe hacer logout sin refresh token', async () => {
      const res = await agent.post('/auth/logout')

      expect(res.statusCode).toBeGreaterThanOrEqual(400)
    })
  })
})
