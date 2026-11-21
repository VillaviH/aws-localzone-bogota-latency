# ¿Vale la pena la AWS Local Zone de Bogotá para usuarios en Ecuador? Medimos y publicamos el código

> BORRADOR. Los números marcados con [ACTUALIZAR LUNES] son preliminares (20 muestras por ruta, una sola ventana). Reemplazar con los datos finales antes de publicar.

*Las opiniones son mías y no representan a AWS.*

## Por qué hice esto

AWS abrió una Local Zone en Bogotá (`us-east-1-bog-1a`). Para muchas empresas de Ecuador y de la región, la pregunta práctica es simple: **si mis usuarios están aquí, ¿mejora algo mover mis servicios allí frente a Virginia (us-east-1), donde ya están casi todos?**

La distancia en el mapa no responde eso. Lo que importa es la ruta que toma el tráfico desde el operador de cada usuario. Así que en lugar de opinar, medí, y dejé todo el código abierto para que cualquiera repita la prueba con su propia conexión.

## Qué construí

- Dos instancias EC2 `c7i.large` idénticas: una en la Local Zone de Bogotá y otra en us-east-1. (`c7i.large` es el tipo más barato disponible en esa zona; no hay t3.)
- Una app Node mínima con `/ping` (JSON pequeño) y `/payload` (1 MB).
- Terraform para crear y destruir todo, y un script (`measure.sh`) que mide conexión TCP, TTFB y tiempo total.
- Un dashboard en HTML que lee los CSV en el navegador y calcula p50, p95, p99, jitter y pérdida.

Medí desde Quito con dos conexiones: fibra óptica y un hotspot sobre red móvil 5G. Cada ubicación se mide en paralelo para que ambas vean las mismas condiciones de red.

## Resultados preliminares [ACTUALIZAR LUNES]

| Conexión | Mediana a Bogotá | Mediana a Virginia | Diferencia |
|---|---|---|---|
| Operador A, fibra | ~42 ms | ~201 ms | Bogotá ~79 % más rápida |
| Operador B, móvil 5G | ~340 ms | ~271 ms | Bogotá ~25 % más lenta |

*(TTFB de `/ping`, en milisegundos. Operador A: 20 muestras por ruta. Operador B: 60.)*

Con el operador A, la diferencia es enorme: el `ping` mínimo hacia Bogotá es de unos 20 ms y hacia Virginia de unos 94 ms. Con el operador B en móvil, ocurrió lo contrario.

**La lectura no es "Bogotá siempre gana" ni "Bogotá no sirve".** Es que el resultado depende de cómo cada operador enruta el tráfico hacia Colombia. Mi hipótesis es que en algunas redes el tráfico no va directo a Bogotá, pero es una hipótesis: la estoy verificando con `mtr` y con más mediciones (incluida una conexión fija del mismo operador, para separar el efecto de la red móvil).

## Qué importa antes de decidir

- **Mide con el operador de tus usuarios reales.** Una prueba desde tu oficina no representa a todos.
- **Mira p95 y p99, no solo el promedio.** Son lo que sienten los usuarios en mal momento.
- **La Local Zone tiene un catálogo de servicios limitado** y depende de su región padre (IAM, consola, plano de control). La latencia es solo una parte de la decisión.
- **Costo:** las instancias en Local Zones suelen costar más que en la región. Revisa precios antes de migrar.
- **Limitaciones de este estudio:** pocas muestras por ventana, una sola ciudad, dos conexiones, protocolo HTTP sin cifrar. Es un punto de partida, no un veredicto.

## Hazlo tú y suma tus datos

Todo está en GitHub: https://github.com/VillaviH/aws-localzone-bogota-latency

1. Clona el repo y activa la Local Zone de Bogotá en tu cuenta.
2. `terraform apply`, corre `measure.sh` desde tu oficina, local o casa.
3. Abre `dashboard.html` y mira tus gráficas.
4. Envía tu CSV por pull request a `data/community/` y vamos construyendo un mapa real de latencia para Ecuador y LATAM.

Recuerda ejecutar `terraform destroy` al terminar: las instancias se cobran por hora.

Si trabajas en una empresa en Ecuador, Perú, Bolivia, Chile u otro país de la región, me interesa especialmente saber qué te sale con tu operador.
