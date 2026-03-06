from fastapi import FastAPI

from .api.routes import router

app = FastAPI(title="{{project_name}}")
app.include_router(router)
