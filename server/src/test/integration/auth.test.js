import request from 'supertest'
import { httpServer } from '../../server.js'
import { pool } from '../../lib/db.js'

const agent = request.agent(httpServer)

const TEST_USER = {
  first_name: 'David',
  paternal_surname: 'Hernandez',
  maternal_surname: 'Chavarria',
  email: 'david.pipeline.test@example.com',
  password: 'password123'
}

describe('🔐 AUTH Endpoints', () => {
  // Preparar BD: limpiar y registrar usuario base una sola vez
  beforeAll(async () => {
    await pool.query("DELETE FROM tokens WHERE user_id IN (SELECT user_id FROM users WHERE email LIKE '%pipeline.test%')")
    await pool.query("DELETE FROM users WHERE email LIKE '%pipeline.test%'")
    // Registrar el usuario base que usan los tests de login
    await agent.post('/auth/register').send(TEST_USER)
  })

  afterAll(async () => {
    await pool.query("DELETE FROM tokens WHERE user_id IN (SELECT user_id FROM users WHERE email LIKE '%pipeline.test%')")
    await pool.query("DELETE FROM users WHERE email LIKE '%pipeline.test%'")
    await pool.end()
    httpServer.close()
  })

  describe('🧩 POST /auth/register', () => {
    it('🚫 No debe permitir registrar un correo ya existente', async () => {
      // El usuario ya fue creado en beforeAll
      const res = await agent.post('/auth/register').send(TEST_USER)
      expect(res.statusCode).toBeGreaterThanOrEqual(400)
      expect(res.body.status).toBe('error')
    })

    it('✅ Debe registrar un nuevo usuario exitosamente', async () => {
      const res = await agent.post('/auth/register').send({
        first_name: 'Nuevo',
        paternal_surname: 'Usuario',
        maternal_surname: 'Test',
        email: 'nuevo.pipeline.test@example.com',
        password: 'password123'
      })
      expect(res.statusCode).toBe(201)
      expect(res.body.success).toBe(true)
      expect(res.body.data.email).toBe('nuevo.pipeline.test@example.com')
      expect(res.body.token).toBeDefined()
    })

    it('🚫 No debe registrar sin campos requeridos', async () => {
      const res = await agent.post('/auth/register').send({
        email: 'incompleto.pipeline.test@example.com'
      })
      expect(res.statusCode).toBeGreaterThanOrEqual(400)
    })
  })

  describe('🔑 POST /auth/login', () => {
    it('✅ Debe iniciar sesión con credenciales válidas', async () => {
      const res = await agent.post('/auth/login').send({
        email: TEST_USER.email,
        password: TEST_USER.password
      })
      expect(res.statusCode).toBe(200)
      expect(res.body.success).toBe(true)
      expect(res.body.data.token).toBeDefined()
      expect(res.body.data.user.email).toBe(TEST_USER.email)
    })

    it('🚫 No debe iniciar sesión con contraseña incorrecta', async () => {
      const res = await agent.post('/auth/login').send({
        email: TEST_USER.email,
        password: 'wrongpassword'
      })
      expect(res.statusCode).toBeGreaterThanOrEqual(400)
      expect(res.body.status).toBe('error')
    })

    it('🚫 No debe iniciar sesión con usuario no registrado', async () => {
      const res = await agent.post('/auth/login').send({
        email: 'noexiste.pipeline.test@example.com',
        password: 'password123'
      })
      expect(res.statusCode).toBeGreaterThanOrEqual(400)
      expect(res.body.status).toBe('error')
    })
  })

  describe('🚪 POST /auth/logout', () => {
    it('🚫 No debe hacer logout sin refresh token', async () => {
      const res = await agent.post('/auth/logout')
      expect(res.statusCode).toBeGreaterThanOrEqual(400)
      expect(res.body.status).toBe('error')
    })
  })
})
