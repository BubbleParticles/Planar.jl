from setuptools import setup, find_packages

setup(
    name="stub_exchanges",
    version="0.1",
    packages=find_packages(),
    include_package_data=True,
    install_requires=[
        "ccxt",
        "fastapi",
        "uvicorn",
    ],
)
